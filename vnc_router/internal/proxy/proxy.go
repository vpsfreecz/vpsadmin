package proxy

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"

	"github.com/gorilla/websocket"
)

type nodeHello struct {
	Token string `json:"token"`
}

// ProxyWSToNode connects to nodectld, sends {"token":"..."}\n, then proxies bytes.
// WS is expected to carry binary RFB frames (noVNC).
func ProxyWSToNode(ctx context.Context, ws *websocket.Conn, nodeHost string, nodePort int, nodeToken string) error {
	dialer := net.Dialer{Timeout: 5 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", fmt.Sprintf("%s:%d", nodeHost, nodePort))
	if err != nil {
		return fmt.Errorf("dial nodectld: %w", err)
	}
	defer conn.Close()

	// Send auth line: {"token":"..."}\n
	bw := bufio.NewWriter(conn)
	hello, _ := json.Marshal(nodeHello{Token: nodeToken})
	if _, err := bw.Write(append(hello, '\n')); err != nil {
		return fmt.Errorf("send hello: %w", err)
	}
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("flush hello: %w", err)
	}

	errCh := make(chan error, 2)

	// WS -> TCP
	go func() {
		for {
			mt, data, err := ws.ReadMessage()
			if err != nil {
				errCh <- err
				return
			}
			if mt != websocket.BinaryMessage {
				// noVNC uses binary; ignore others
				continue
			}
			if _, err := conn.Write(data); err != nil {
				errCh <- err
				return
			}
		}
	}()

	// TCP -> WS
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				if werr := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); werr != nil {
					errCh <- werr
					return
				}
			}
			if err != nil {
				if err == io.EOF {
					errCh <- err
				} else {
					errCh <- err
				}
				return
			}
		}
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-errCh:
		return err
	}
}
