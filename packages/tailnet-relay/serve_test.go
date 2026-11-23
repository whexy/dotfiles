package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"io"
	"math/big"
	"net"
	"testing"
	"time"
)

// listenPair returns both ends of a loopback TCP connection.
func listenPair(t *testing.T) (net.Conn, net.Conn) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	server, err := ln.Accept()
	if err != nil {
		t.Fatal(err)
	}
	return client, server
}

// A caller that half-closes still reads the target's reply, as ssh does when
// its input ends.
func TestPipePassesHalfClose(t *testing.T) {
	caller, relayIn := listenPair(t)
	relayOut, target := listenPair(t)
	defer caller.Close()
	defer target.Close()
	done := make(chan struct{})
	go func() { pipe(relayIn, relayOut); close(done) }()

	caller.Write([]byte("ping"))
	caller.(*net.TCPConn).CloseWrite()
	got, err := io.ReadAll(target)
	if err != nil || string(got) != "ping" {
		t.Fatalf("target read %q, %v", got, err)
	}
	target.Write([]byte("pong"))
	target.Close()
	got, err = io.ReadAll(caller)
	if err != nil || string(got) != "pong" {
		t.Fatalf("caller read %q, %v", got, err)
	}
	<-done
}

// A TLS serve relays the plaintext both ways, and a caller's close_notify
// reaches the target as the end of its input.
func TestPipeEndsTLS(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		DNSNames:     []string{"relay.test"},
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert := tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}

	rawCaller, rawRelayIn := listenPair(t)
	relayIn := tls.Server(rawRelayIn, &tls.Config{Certificates: []tls.Certificate{cert}})
	caller := tls.Client(rawCaller, &tls.Config{ServerName: "relay.test", InsecureSkipVerify: true})
	relayOut, target := listenPair(t)
	defer caller.Close()
	defer target.Close()
	done := make(chan struct{})
	go func() { pipe(relayIn, relayOut); close(done) }()

	if _, err := caller.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	caller.CloseWrite()
	got, err := io.ReadAll(target)
	if err != nil || string(got) != "ping" {
		t.Fatalf("target read %q, %v", got, err)
	}
	target.Write([]byte("pong"))
	target.Close()
	got, err = io.ReadAll(caller)
	if err != nil || string(got) != "pong" {
		t.Fatalf("caller read %q, %v", got, err)
	}
	<-done
}
