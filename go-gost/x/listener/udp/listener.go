package udp

import (
	"net"

	"github.com/go-gost/core/limiter"
	"github.com/go-gost/core/listener"
	"github.com/go-gost/core/logger"
	md "github.com/go-gost/core/metadata"
	admission "github.com/go-gost/x/admission/wrapper"
	xnet "github.com/go-gost/x/internal/net"
	"github.com/go-gost/x/internal/net/udp"
	climiter "github.com/go-gost/x/limiter/conn/wrapper"
	traffic_limiter "github.com/go-gost/x/limiter/traffic"
	limiter_wrapper "github.com/go-gost/x/limiter/traffic/wrapper"
	metrics "github.com/go-gost/x/metrics/wrapper"
	stats "github.com/go-gost/x/observer/stats/wrapper"
	"github.com/go-gost/x/registry"
)

func init() {
	registry.ListenerRegistry().Register("udp", NewListener)
}

type udpListener struct {
	ln      net.Listener
	logger  logger.Logger
	md      metadata
	options listener.Options
}

func NewListener(opts ...listener.Option) listener.Listener {
	options := listener.Options{}
	for _, opt := range opts {
		opt(&options)
	}
	return &udpListener{
		logger:  options.Logger,
		options: options,
	}
}

func (l *udpListener) Init(md md.Metadata) (err error) {
	if err = l.parseMetadata(md); err != nil {
		return
	}

	network := "udp"
	if xnet.IsIPv4(l.options.Addr) {
		network = "udp4"
	}
	laddr, err := net.ResolveUDPAddr(network, l.options.Addr)
	if err != nil {
		return
	}

	var conn net.PacketConn
	conn, err = net.ListenUDP(network, laddr)
	if err != nil {
		return
	}
	conn = metrics.WrapPacketConn(l.options.Service, conn)
	conn = stats.WrapPacketConn(conn, l.options.Stats)
	conn = admission.WrapPacketConn(l.options.Admission, conn)
	conn = limiter_wrapper.WrapPacketConn(
		conn,
		l.options.TrafficLimiter,
		traffic_limiter.ServiceLimitKey,
		limiter.ScopeOption(limiter.ScopeService),
		limiter.ServiceOption(l.options.Service),
		limiter.NetworkOption(conn.LocalAddr().Network()),
	)

	ln := udp.NewListener(conn, &udp.ListenConfig{
		Backlog:        l.md.backlog,
		ReadQueueSize:  l.md.readQueueSize,
		ReadBufferSize: l.md.readBufferSize,
		Keepalive:      l.md.keepalive,
		TTL:            l.md.ttl,
		Logger:         l.logger,
	})
	l.ln = ln
	return
}

func (l *udpListener) Accept() (conn net.Conn, err error) {
	conn, err = l.ln.Accept()
	if err != nil {
		return
	}

	if l.options.ConnLimiter != nil {
		host, _, _ := net.SplitHostPort(conn.RemoteAddr().String())
		if lim := l.options.ConnLimiter.Limiter(host); lim != nil {
			if !lim.Allow(1) {
				_ = conn.Close()
				return closedConn{Conn: conn}, nil
			}
			conn = climiter.WrapConn(lim, conn)
		}
	}

	conn = limiter_wrapper.WrapConn(
		conn,
		l.options.TrafficLimiter,
		conn.RemoteAddr().String(),
		limiter.ScopeOption(limiter.ScopeConn),
		limiter.ServiceOption(l.options.Service),
		limiter.NetworkOption(conn.LocalAddr().Network()),
		limiter.SrcOption(conn.RemoteAddr().String()),
	)
	return
}

type closedConn struct {
	net.Conn
}

func (c closedConn) Read([]byte) (int, error) {
	return 0, net.ErrClosed
}

func (c closedConn) Write([]byte) (int, error) {
	return 0, net.ErrClosed
}

func (l *udpListener) Addr() net.Addr {
	return l.ln.Addr()
}

func (l *udpListener) Close() error {
	return l.ln.Close()
}
