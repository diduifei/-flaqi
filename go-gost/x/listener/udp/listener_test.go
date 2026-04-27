package udp

import (
	"io"
	"net"
	"testing"
	"time"

	corelistener "github.com/go-gost/core/listener"
	corelogger "github.com/go-gost/core/logger"
	xconn "github.com/go-gost/x/limiter/conn"
	xlogger "github.com/go-gost/x/logger"
)

func TestAcceptAppliesConnLimiterAndReleasesOnClose(t *testing.T) {
	ln := NewListener(
		corelistener.AddrOption("127.0.0.1:0"),
		corelistener.ConnLimiterOption(xconn.NewConnLimiter(
			xconn.LimitsOption("$$ 1"),
			xconn.LoggerOption(xlogger.NewLogger(xlogger.OutputOption(io.Discard), xlogger.LevelOption(corelogger.ErrorLevel))),
		)),
		corelistener.LoggerOption(xlogger.NewLogger(xlogger.OutputOption(io.Discard), xlogger.LevelOption(corelogger.ErrorLevel))),
	)
	if err := ln.Init(nil); err != nil {
		t.Fatalf("init listener: %v", err)
	}
	defer ln.Close()

	addr := ln.Addr().String()
	client, err := net.Dial("udp", addr)
	if err != nil {
		t.Fatalf("dial udp listener: %v", err)
	}
	defer client.Close()
	if _, err := client.Write([]byte("first")); err != nil {
		t.Fatalf("write first packet: %v", err)
	}
	first, err := acceptWithTimeout(t, ln, time.Second)
	if err != nil {
		t.Fatalf("accept first conn: %v", err)
	}

	blockedClient, err := net.Dial("udp", addr)
	if err != nil {
		t.Fatalf("dial blocked udp client: %v", err)
	}
	defer blockedClient.Close()
	if _, err := blockedClient.Write([]byte("blocked")); err != nil {
		t.Fatalf("write blocked packet: %v", err)
	}
	blocked, err := acceptWithTimeout(t, ln, time.Second)
	if err != nil {
		t.Fatalf("expected blocked same-IP pseudo-connection to be returned closed: %v", err)
	}
	buf := make([]byte, 16)
	if _, err := blocked.Read(buf); err == nil {
		_ = blocked.Close()
		t.Fatalf("expected blocked same-IP pseudo-connection to be closed")
	}
	_ = blocked.Close()
	_ = first.Close()

	reopenedClient, err := net.Dial("udp", addr)
	if err != nil {
		t.Fatalf("dial reopened udp client: %v", err)
	}
	defer reopenedClient.Close()
	if _, err := reopenedClient.Write([]byte("after-close")); err != nil {
		t.Fatalf("write after close packet: %v", err)
	}
	reopened, err := acceptWithTimeout(t, ln, time.Second)
	if err != nil {
		t.Fatalf("expected same client to be accepted after close: %v", err)
	}
	_ = reopened.Close()
}

func acceptWithTimeout(t *testing.T, ln corelistener.Listener, timeout time.Duration) (net.Conn, error) {
	t.Helper()
	type result struct {
		conn net.Conn
		err  error
	}
	ch := make(chan result, 1)
	go func() {
		conn, err := ln.Accept()
		ch <- result{conn: conn, err: err}
	}()
	select {
	case res := <-ch:
		return res.conn, res.err
	case <-time.After(timeout):
		return nil, net.ErrClosed
	}
}
