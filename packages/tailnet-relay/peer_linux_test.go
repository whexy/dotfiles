package main

import (
	"net"
	"os"
	"testing"
)

func TestPeerUIDOfOwnConnection(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	conn, err := ln.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	uid, err := peerUID(conn)
	if err != nil {
		t.Fatal(err)
	}
	if uid != uint32(os.Getuid()) {
		t.Fatalf("peer uid %d, want %d", uid, os.Getuid())
	}
}

func TestPeerUIDOfClosedClient(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	conn, err := ln.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	// A client socket that is gone cannot be attributed, and is refused.
	client.(*net.TCPConn).SetLinger(0)
	client.Close()

	if uid, err := peerUID(conn); err == nil {
		t.Fatalf("closed client attributed to uid %d", uid)
	}
}

func TestLoadConfigRejectsNonLoopbackListener(t *testing.T) {
	path := t.TempDir() + "/config.json"
	body := `{"hostname":"h","stateDir":"/tmp/s","forwards":[{"name":"a","listen":"0.0.0.0:1","upstream":"https://a.example"}]}`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfig(path); err == nil {
		t.Fatal("0.0.0.0 accepted")
	}
}
