package rpc

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

var (
	ErrTimeout = errors.New("rpc timeout")
	ErrServer  = errors.New("rpc server error")
)

type Client struct {
	url        string
	exchange   string
	routingKey string
	softTO     time.Duration
	hardTO     time.Duration
	debug      bool

	mu    sync.Mutex
	conn  *amqp.Connection
	ch    *amqp.Channel
	reply amqp.Queue

	// One consumer for reply queue
	deliveries <-chan amqp.Delivery
	consumerUp bool

	// correlation_id -> response channel
	waiters map[string]chan amqp.Delivery

	// closed when we tear down connection/channel/consumer
	stopCh chan struct{}
}

type requestPayload struct {
	Command string         `json:"command"`
	Args    []any          `json:"args"`
	Kwargs  map[string]any `json:"kwargs"`
}

type responsePayload struct {
	Status   bool            `json:"status"`
	Message  string          `json:"message"`
	Response json.RawMessage `json:"response"`
}

func New(url, exchange, routingKey string, softTimeout, hardTimeout time.Duration, debug bool) *Client {
	return &Client{
		url:        url,
		exchange:   exchange,
		routingKey: routingKey,
		softTO:     softTimeout,
		hardTO:     hardTimeout,
		debug:      debug,
		waiters:    make(map[string]chan amqp.Delivery),
		stopCh:     make(chan struct{}),
	}
}

func (c *Client) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.teardownLocked()

	// Close stopCh to stop any dispatcher
	select {
	case <-c.stopCh:
		// already closed
	default:
		close(c.stopCh)
	}
}

func (c *Client) teardownLocked() {
	// Fail all waiters
	for id, ch := range c.waiters {
		close(ch)
		delete(c.waiters, id)
	}

	c.consumerUp = false
	c.deliveries = nil

	if c.ch != nil {
		_ = c.ch.Close()
		c.ch = nil
	}
	if c.conn != nil {
		_ = c.conn.Close()
		c.conn = nil
	}
}

// ensureConnectedLocked sets up conn/channel/exchange/replyQ and single consumer.
// MUST be called with c.mu held.
func (c *Client) ensureConnectedLocked() error {
	// Already good?
	if c.conn != nil && !c.conn.IsClosed() && c.ch != nil && c.consumerUp && c.deliveries != nil {
		return nil
	}

	// Tear down anything stale
	c.teardownLocked()

	conn, err := amqp.Dial(c.url)
	if err != nil {
		return fmt.Errorf("amqp dial: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		_ = conn.Close()
		return fmt.Errorf("amqp channel: %w", err)
	}

	// Exchange must NOT be durable (per your correction).
	// Declaring it is safe if server declares it identically.
	if err := ch.ExchangeDeclare(
		c.exchange,
		"direct",
		false, // durable ❌
		false, // auto-delete
		false,
		false,
		nil,
	); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("exchange declare: %w", err)
	}

	// Exclusive auto-delete reply queue
	q, err := ch.QueueDeclare(
		"",
		false, // durable
		true,  // auto-delete
		true,  // exclusive
		false,
		nil,
	)
	if err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("reply queue declare: %w", err)
	}

	// Bind reply queue to exchange with routing_key = queue_name (Ruby style)
	if err := ch.QueueBind(q.Name, q.Name, c.exchange, false, nil); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("reply queue bind: %w", err)
	}

	// Start ONE consumer for the reply queue (no exclusive consumer-per-call!)
	deliveries, err := ch.Consume(
		q.Name,
		"",
		true,  // auto-ack
		true,  // exclusive consumer (only one) — and we only create it once
		false, // no-local
		false, // no-wait
		nil,
	)
	if err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("consume reply queue: %w", err)
	}

	c.conn = conn
	c.ch = ch
	c.reply = q
	c.deliveries = deliveries
	c.consumerUp = true

	// Start dispatcher once per successful setup.
	go c.dispatchReplies(deliveries)

	return nil
}

// dispatchReplies runs until deliveries closes or client stopCh closes.
// It routes deliveries by correlation_id to the waiting Call().
func (c *Client) dispatchReplies(deliveries <-chan amqp.Delivery) {
	for {
		select {
		case <-c.stopCh:
			return
		case d, ok := <-deliveries:
			if !ok {
				// Connection/channel died. Next call will reconnect.
				c.mu.Lock()
				// If deliveries matches current one, mark dead + teardown
				if c.deliveries == deliveries {
					c.teardownLocked()
				}
				c.mu.Unlock()
				return
			}

			c.mu.Lock()
			ch := c.waiters[d.CorrelationId]
			if ch != nil {
				// Non-blocking send; waiter channel is buffered 1, but be safe.
				select {
				case ch <- d:
				default:
				}
			}
			c.mu.Unlock()
		}
	}
}

func genID() string {
	var b [20]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

// Call sends {command,args,kwargs} and unmarshals `response` into out.
func (c *Client) Call(ctx context.Context, command string, args []any, kwargs map[string]any, out any) error {
	callID := genID()
	if kwargs == nil {
		kwargs = map[string]any{}
	}

	req := requestPayload{
		Command: command,
		Args:    args,
		Kwargs:  kwargs,
	}

	body, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}

	if c.debug {
		log.Printf("rpc request id=%s cmd=%s args=%v kwargs=%v", callID[:8], command, args, kwargs)
	}

	softWarnAt := time.Now().Add(c.softTO)
	hardDeadline := time.Now().Add(c.hardTO)

	// Create waiter
	respCh := make(chan amqp.Delivery, 1)

	for {
		// Ensure connection + consumer
		c.mu.Lock()
		err = c.ensureConnectedLocked()
		ch := c.ch
		replyTo := c.reply.Name
		if err == nil {
			c.waiters[callID] = respCh
		}
		c.mu.Unlock()

		if err != nil {
			log.Printf("rpc: ensure failed: %v (retry in 5s)", err)
			select {
			case <-time.After(5 * time.Second):
				continue
			case <-ctx.Done():
				return ctx.Err()
			}
		}

		// Publish request
		pub := amqp.Publishing{
			DeliveryMode:  amqp.Persistent,
			ContentType:   "application/json",
			CorrelationId: callID,
			ReplyTo:       replyTo,
			Body:          body,
		}

		pubCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err = ch.PublishWithContext(pubCtx, c.exchange, c.routingKey, false, false, pub)
		cancel()

		if err != nil {
			log.Printf("rpc: publish failed: %v (retry in 5s)", err)
			// Cleanup waiter registration and force reconnect
			c.mu.Lock()
			delete(c.waiters, callID)
			c.teardownLocked()
			c.mu.Unlock()

			select {
			case <-time.After(5 * time.Second):
				continue
			case <-ctx.Done():
				return ctx.Err()
			}
		}

		// Wait for response by correlation ID
		for {
			now := time.Now()
			if now.After(hardDeadline) {
				c.mu.Lock()
				delete(c.waiters, callID)
				c.mu.Unlock()
				return fmt.Errorf("%w: no reply for %s cmd=%s", ErrTimeout, c.hardTO, command)
			}
			if now.After(softWarnAt) {
				log.Printf("rpc: waiting id=%s cmd=%s", callID[:8], command)
				softWarnAt = now.Add(c.softTO)
			}

			select {
			case d, ok := <-respCh:
				// ok==false means teardown closed respCh (connection died)
				c.mu.Lock()
				delete(c.waiters, callID)
				c.mu.Unlock()

				if !ok {
					// Reconnect and retry
					log.Printf("rpc: response channel closed (retry in 5s)")
					select {
					case <-time.After(5 * time.Second):
						goto retry
					case <-ctx.Done():
						return ctx.Err()
					}
				}

				var resp responsePayload
				if err := json.Unmarshal(d.Body, &resp); err != nil {
					return fmt.Errorf("unmarshal rpc response: %w", err)
				}

				if c.debug {
					log.Printf("rpc response id=%s ok=%v msg=%q", callID[:8], resp.Status, resp.Message)
				}

				if !resp.Status {
					if resp.Message == "" {
						resp.Message = "Server error"
					}
					return fmt.Errorf("%w: %s", ErrServer, resp.Message)
				}

				if out == nil {
					return nil
				}
				if err := json.Unmarshal(resp.Response, out); err != nil {
					return fmt.Errorf("unmarshal response payload: %w", err)
				}
				return nil

			case <-time.After(250 * time.Millisecond):
				// loop to check deadlines / soft warnings
			case <-ctx.Done():
				c.mu.Lock()
				delete(c.waiters, callID)
				c.mu.Unlock()
				return ctx.Err()
			}
		}
	retry:
		continue
	}
}

// RPC response structure for "get_vnc_target"
type VncTarget struct {
	NodeHost  string `json:"node_host"`
	NodePort  int    `json:"node_port"`
	NodeToken string `json:"node_token"`
}

func (c *Client) GetVncTarget(ctx context.Context, accessToken string) (*VncTarget, error) {
	var out VncTarget
	if err := c.Call(ctx, "get_vnc_target", []any{accessToken}, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
