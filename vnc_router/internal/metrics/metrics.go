package metrics

import (
	"fmt"
	"io"
	"sort"
	"sync"
	"sync/atomic"
)

// Metrics keeps track of connected clients and their traffic.
type Metrics struct {
	mu       sync.Mutex
	current  map[int]int    // vps_id -> currently connected
	total    map[int]uint64 // vps_id -> lifetime connections
	sent     map[int]uint64 // vps_id -> bytes client -> node
	received map[int]uint64 // vps_id -> bytes node -> client
}

func New() *Metrics {
	return &Metrics{
		current:  make(map[int]int),
		total:    make(map[int]uint64),
		sent:     make(map[int]uint64),
		received: make(map[int]uint64),
	}
}

// ConnMetrics represents one authenticated client session.
type ConnMetrics struct {
	m      *Metrics
	vpsID  int
	closed atomic.Bool
}

// NewConnection records a new verified client connection.
func (m *Metrics) NewConnection(vpsID int) *ConnMetrics {
	m.mu.Lock()
	m.current[vpsID]++
	m.total[vpsID]++
	m.mu.Unlock()

	return &ConnMetrics{m: m, vpsID: vpsID}
}

// AddClientToNode adds bytes sent from client to node.
func (c *ConnMetrics) AddClientToNode(n int) {
	if n <= 0 {
		return
	}
	c.m.mu.Lock()
	c.m.sent[c.vpsID] += uint64(n)
	c.m.mu.Unlock()
}

// AddNodeToClient adds bytes sent from node to client.
func (c *ConnMetrics) AddNodeToClient(n int) {
	if n <= 0 {
		return
	}
	c.m.mu.Lock()
	c.m.received[c.vpsID] += uint64(n)
	c.m.mu.Unlock()
}

// Done decrements current connection count.
func (c *ConnMetrics) Done() {
	if c.closed.Swap(true) {
		return
	}
	c.m.mu.Lock()
	if cur := c.m.current[c.vpsID]; cur > 0 {
		c.m.current[c.vpsID] = cur - 1
	}
	c.m.mu.Unlock()
}

// ExportPrometheus writes metrics in text format.
func (m *Metrics) ExportPrometheus(w io.Writer) {
	m.mu.Lock()
	defer m.mu.Unlock()

	fmt.Fprintln(w, "# HELP vnc_router_clients_connected Current connected VNC clients per VPS.")
	fmt.Fprintln(w, "# TYPE vnc_router_clients_connected gauge")
	for _, vpsID := range m.sortedVpsIDs() {
		fmt.Fprintf(w, "vnc_router_clients_connected{vps_id=\"%d\"} %d\n", vpsID, m.current[vpsID])
	}

	fmt.Fprintln(w, "# HELP vnc_router_clients_total Total authenticated VNC clients per VPS.")
	fmt.Fprintln(w, "# TYPE vnc_router_clients_total counter")
	for _, vpsID := range m.sortedVpsIDs() {
		fmt.Fprintf(w, "vnc_router_clients_total{vps_id=\"%d\"} %d\n", vpsID, m.total[vpsID])
	}

	fmt.Fprintln(w, "# HELP vnc_router_client_bytes_sent_total Bytes sent from client to node per VPS.")
	fmt.Fprintln(w, "# TYPE vnc_router_client_bytes_sent_total counter")
	for _, vpsID := range m.sortedVpsIDs() {
		fmt.Fprintf(w, "vnc_router_client_bytes_sent_total{vps_id=\"%d\"} %d\n", vpsID, m.sent[vpsID])
	}

	fmt.Fprintln(w, "# HELP vnc_router_client_bytes_received_total Bytes sent from node to client per VPS.")
	fmt.Fprintln(w, "# TYPE vnc_router_client_bytes_received_total counter")
	for _, vpsID := range m.sortedVpsIDs() {
		fmt.Fprintf(w, "vnc_router_client_bytes_received_total{vps_id=\"%d\"} %d\n", vpsID, m.received[vpsID])
	}
}

func (m *Metrics) sortedVpsIDs() []int {
	seen := make(map[int]struct{})
	for k := range m.current {
		seen[k] = struct{}{}
	}
	for k := range m.total {
		seen[k] = struct{}{}
	}
	for k := range m.sent {
		seen[k] = struct{}{}
	}
	for k := range m.received {
		seen[k] = struct{}{}
	}

	ids := make([]int, 0, len(seen))
	for id := range seen {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	return ids
}
