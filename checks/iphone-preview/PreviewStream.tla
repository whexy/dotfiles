---------------------------- MODULE PreviewStream ----------------------------
(* The live preview of one iPhone in one iPhone Use server process, the
   viewer. Its frames come from curl reading WebDriverAgent's MJPEG port
   through iphone-use-select's loopback relay.

   Code, in iPhone Use's server/ with packages/iphone-use/mjpeg-relay.patch:
     wda_screen.py  ScreenHub.frame, _wire, close, set_paused, _live,
                    _run, _publish_frame, _command
     iphone_use.py  serve (which thread runs which request), _dispatch,
                    Runtime's automatic pause on a secure field
   and packages/iphone-wda/iphone_use_select.py, which sets
   IPHONE_USE_MJPEG_URL.

   Each action is one step the code takes without another thread in
   between: a section under ScreenHub._lock, one screen-state.json
   transaction, or one check in _run's loops. close() is one step although
   it terminates curl after releasing the lock: the stream thread reacts to
   stop, which close() sets under the lock, not to curl's exit. *)
EXTENDS Naturals, Sequences

CONSTANTS
    Pauser,       \* who pauses the preview before the user authenticates
    StallTimeout, \* curl runs with --speed-limit and --speed-time
    MaxStalls     \* how many times the relayed connection may go silent

\* "reader":  the agent's pua_screen(action=pause), on serve's request thread
\* "worker":  the pause a phone tool makes on a secure field, on the worker
\* "process": another iPhone Use process on this host, same state file
\* "host":    an iPhone Use process on another host, its own state file
Pausers == {"reader", "worker", "process", "host"}
ASSUME Pauser \in Pausers /\ StallTimeout \in BOOLEAN /\ MaxStalls \in Nat

VARIABLES
    screen,     \* what the phone shows: "normal", or "secret" while the user authenticates
    auth,       \* the pause around authentication, see AuthPhases
    paused,     \* "paused" in this host's screen-state.json
    visible,    \* the panel is on screen, so the widget polls pua_screen_frame
    poll,       \* the request thread's frame(): "idle", "read" (state read), "wire"
    pollPaused, \* the paused flag that frame() read
    lease,      \* time.monotonic() < _lease_until
    stop,       \* the stream thread's stop Event is set
    thread,     \* where the stream thread is in _run, see ThreadPcs
    childRef,   \* self._child holds the running curl
    curl,       \* the curl process: "none", "running", "exited"
    conn,       \* curl's connection through the relay: "ok", "stalled"
    stalls,     \* times the connection has gone silent
    pipe,       \* a frame on its way from the phone to the parser, at most one
    parsed,     \* the frame _run holds between parsing and publishing
    frame,      \* self._frame: "none", "normal", "secret"
    served      \* the screens frame() has returned to the widget

vars == <<screen, auth, paused, visible, poll, pollPaused, lease, stop, thread,
          childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* "wrote": the pause is in the state file; close() has not run yet.
\* "paused": set_paused returned, so the agent hands the phone to the user.
AuthPhases == {"idle", "wrote", "paused", "takeover", "done"}
\* "top": while self._live(stop); "spawned": Popen returned, _child not set;
\* "loop": while self._live(stop) and child.poll() is None;
\* "select": waiting for a chunk; "parsed": a frame parsed, before its
\* _live check; "checked": before _publish_frame; "cleanup": finally;
\* "backoff": the wait before the next connection; "none": not alive.
ThreadPcs == {"none", "top", "spawned", "loop", "select", "parsed",
              "checked", "cleanup", "backoff"}
Screens == {"normal", "secret"}

TypeOK ==
    /\ screen \in Screens
    /\ auth \in AuthPhases
    /\ paused \in BOOLEAN /\ visible \in BOOLEAN /\ pollPaused \in BOOLEAN
    /\ poll \in {"idle", "read", "wire"}
    /\ lease \in BOOLEAN /\ stop \in BOOLEAN /\ childRef \in BOOLEAN
    /\ thread \in ThreadPcs
    /\ curl \in {"none", "running", "exited"}
    /\ conn \in {"ok", "stalled"}
    /\ stalls \in 0..MaxStalls
    /\ pipe \in Seq(Screens) /\ Len(pipe) <= 1
    /\ parsed \in Screens \cup {"none"}
    /\ frame \in Screens \cup {"none"}
    /\ served \subseteq Screens

Init ==
    /\ screen = "normal" /\ auth = "idle" /\ paused = FALSE
    /\ visible = FALSE /\ poll = "idle" /\ pollPaused = FALSE
    /\ lease = FALSE /\ stop = FALSE /\ thread = "none" /\ childRef = FALSE
    /\ curl = "none" /\ conn = "ok" /\ stalls = 0 /\ pipe = <<>>
    /\ parsed = "none" /\ frame = "none" /\ served = {}

\* _live(stop): the lease holds, stop is clear, and the state file is not paused.
Live == lease /\ ~stop /\ ~paused

\* Only the viewer's own pausers call its close().
OwnPauser == Pauser \in {"reader", "worker"}

\* serve's request thread runs frame polls and pua_screen one at a time.
ReaderBusy == Pauser = "reader" /\ auth = "wrote"

\* close(): under the lock, clear the lease, set stop and drop the frame;
\* then terminate the child the lock showed.
CloseEffects ==
    /\ lease' = FALSE /\ stop' = TRUE /\ frame' = "none"
    /\ curl' = IF childRef /\ curl = "running" THEN "exited" ELSE curl

----------------------------------------------------------------------------
\* The widget and its frame() polls, on serve's request thread.

PanelOpens ==
    /\ ~visible
    /\ visible' = TRUE
    /\ UNCHANGED <<screen, auth, paused, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

PanelCloses ==
    /\ visible
    /\ visible' = FALSE
    /\ UNCHANGED <<screen, auth, paused, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* frame(): state = self._read_state()
PollReadsState ==
    /\ visible
    /\ poll = "idle"
    /\ ~ReaderBusy
    /\ poll' = "read" /\ pollPaused' = paused
    /\ UNCHANGED <<screen, auth, paused, visible, lease, stop, thread, childRef,
                   curl, conn, stalls, pipe, parsed, frame, served>>

\* frame(): close() when paused; else renew the lease and start a stream
\* thread, with a fresh stop Event, if none is alive.
PollLeases ==
    /\ poll = "read"
    /\ poll' = "wire"
    /\ IF pollPaused
       THEN CloseEffects /\ UNCHANGED thread
       ELSE /\ lease' = TRUE
            /\ IF thread = "none"
               THEN thread' = "top" /\ stop' = FALSE
               ELSE UNCHANGED <<thread, stop>>
            /\ UNCHANGED <<frame, curl>>
    /\ UNCHANGED <<screen, auth, paused, visible, pollPaused, childRef, conn,
                   stalls, pipe, parsed, served>>

\* _wire(state): under the lock, the frame unless the state read was paused.
PollReturns ==
    /\ poll = "wire"
    /\ poll' = "idle"
    /\ served' = (IF ~pollPaused /\ frame # "none" THEN served \cup {frame} ELSE served)
    /\ UNCHANGED <<screen, auth, paused, visible, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame>>

\* No poll for FRAME_LEASE_SECONDS.
LeaseExpires ==
    /\ lease
    /\ ~visible
    /\ poll = "idle"
    /\ lease' = FALSE
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

----------------------------------------------------------------------------
\* The stream thread, _run.

StreamStarts ==
    /\ thread = "top"
    /\ IF Live
       THEN /\ thread' = "spawned" /\ curl' = "running" /\ conn' = "ok"
            /\ pipe' = <<>>
       ELSE thread' = "none" /\ UNCHANGED <<curl, conn, pipe>>
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, stalls, parsed, frame, served>>

\* with self._lock: self._child = child
StreamRecordsChild ==
    /\ thread = "spawned"
    /\ thread' = "loop"
    /\ childRef' = TRUE
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   curl, conn, stalls, pipe, parsed, frame, served>>

StreamLoops ==
    /\ thread = "loop"
    /\ thread' = (IF Live /\ curl = "running" THEN "select" ELSE "cleanup")
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* os.read and parser.feed: one frame per chunk.
StreamReads ==
    /\ thread = "select"
    /\ pipe # <<>>
    /\ thread' = "parsed" /\ parsed' = Head(pipe) /\ pipe' = Tail(pipe)
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, frame, served>>

\* select's 0.1 s timeout, or the empty read when curl has exited.
StreamWaits ==
    /\ thread = "select"
    /\ pipe = <<>>
    /\ thread' = (IF curl = "running" THEN "loop" ELSE "cleanup")
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* if not self._live(stop): break
StreamChecksFrame ==
    /\ thread = "parsed"
    /\ thread' = (IF Live THEN "checked" ELSE "cleanup")
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* _publish_frame: under the lock, nothing once stop is set.
StreamPublishes ==
    /\ thread = "checked"
    /\ thread' = "loop"
    /\ frame' = (IF stop THEN frame ELSE parsed)
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, pipe, parsed, served>>

\* finally: terminate curl; under the lock, forget it and drop the frame if paused.
StreamCleansUp ==
    /\ thread = "cleanup"
    /\ thread' = "backoff"
    /\ curl' = "none" /\ childRef' = FALSE /\ pipe' = <<>> /\ parsed' = "none"
    /\ frame' = (IF paused THEN "none" ELSE frame)
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   conn, stalls, served>>

StreamBacksOff ==
    /\ thread = "backoff"
    /\ thread' = "top"
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

----------------------------------------------------------------------------
\* The phone, the relay and curl.

PhoneSendsFrame ==
    /\ curl = "running"
    /\ conn = "ok"
    /\ pipe = <<>>
    /\ pipe' = <<screen>>
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   thread, childRef, curl, conn, stalls, parsed, frame, served>>

ConnectionStalls ==
    /\ curl = "running"
    /\ conn = "ok"
    /\ stalls < MaxStalls
    /\ conn' = "stalled" /\ stalls' = stalls + 1
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   thread, childRef, curl, pipe, parsed, frame, served>>

\* --speed-limit 1 --speed-time 5: curl exits after 5 s without data.
CurlGivesUp ==
    /\ StallTimeout
    /\ curl = "running"
    /\ conn = "stalled"
    /\ curl' = "exited"
    /\ UNCHANGED <<screen, auth, paused, visible, poll, pollPaused, lease, stop,
                   thread, childRef, conn, stalls, pipe, parsed, frame, served>>

----------------------------------------------------------------------------
\* Authentication: set_paused(True), the user's takeover, set_paused(False).

\* set_paused's state transaction. The other host writes its own file.
PauseWritten ==
    /\ auth = "idle"
    /\ (Pauser = "reader" => poll = "idle")
    /\ auth' = "wrote"
    /\ paused' = (Pauser # "host" \/ paused)
    /\ UNCHANGED <<screen, visible, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* set_paused then calls its own process's close().
PauseReturns ==
    /\ auth = "wrote"
    /\ auth' = "paused"
    /\ IF OwnPauser
       THEN CloseEffects
       ELSE UNCHANGED <<lease, stop, frame, curl>>
    /\ UNCHANGED <<screen, paused, visible, poll, pollPaused, thread, childRef,
                   conn, stalls, pipe, parsed, served>>

\* Timing the model has no clock for: the user starts seconds after the pause
\* returns, since the agent asks first, while _run checks the state file at
\* least every 0.1 s (select's timeout) and on each frame. So by then the
\* viewer's stream thread has seen the pause in the file: it is cleaning up,
\* backing off, about to exit, or gone. The viewer's own pauses need no such
\* assumption: close() sets stop.
UserAuthenticates ==
    /\ auth = "paused"
    /\ (Pauser = "process" /\ paused) =>
           thread \in {"none", "top", "cleanup", "backoff"}
    /\ auth' = "takeover"
    /\ screen' = "secret"
    /\ UNCHANGED <<paused, visible, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

UserFinishes ==
    /\ auth = "takeover"
    /\ auth' = "done"
    /\ screen' = "normal"
    /\ UNCHANGED <<paused, visible, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

\* pua_screen(action=resume), on the pausing process's request thread.
AgentResumes ==
    /\ auth = "done"
    /\ (OwnPauser => poll = "idle")
    /\ auth' = "idle"
    /\ paused' = (Pauser = "host" /\ paused)
    /\ UNCHANGED <<screen, visible, poll, pollPaused, lease, stop, thread,
                   childRef, curl, conn, stalls, pipe, parsed, frame, served>>

----------------------------------------------------------------------------

System ==
    \/ PollReadsState \/ PollLeases \/ PollReturns \/ LeaseExpires
    \/ StreamStarts \/ StreamRecordsChild \/ StreamLoops \/ StreamReads
    \/ StreamWaits \/ StreamChecksFrame \/ StreamPublishes \/ StreamCleansUp
    \/ StreamBacksOff \/ PhoneSendsFrame \/ CurlGivesUp

Environment ==
    \/ PanelOpens \/ PanelCloses \/ ConnectionStalls
    \/ PauseWritten \/ PauseReturns \/ UserAuthenticates \/ UserFinishes
    \/ AgentResumes

Next == System \/ Environment

\* Threads, curl and the phone keep running; the user and the network need not.
Fairness ==
    /\ WF_vars(PollReadsState) /\ WF_vars(PollLeases) /\ WF_vars(PollReturns)
    /\ WF_vars(LeaseExpires)
    /\ WF_vars(StreamStarts) /\ WF_vars(StreamRecordsChild) /\ WF_vars(StreamLoops)
    /\ WF_vars(StreamReads) /\ WF_vars(StreamWaits) /\ WF_vars(StreamChecksFrame)
    /\ WF_vars(StreamPublishes) /\ WF_vars(StreamCleansUp) /\ WF_vars(StreamBacksOff)
    /\ WF_vars(PhoneSendsFrame) /\ WF_vars(CurlGivesUp)
    /\ WF_vars(PauseReturns)

Spec == Init /\ [][Next]_vars /\ Fairness

----------------------------------------------------------------------------
\* Rules.

\* The panel never shows the phone while the user authenticates.
NeverShown == "secret" \notin served

\* The viewer never keeps a frame of it as the frame a poll can return.
NeverKept == frame # "secret"

\* Once its own process's pause returns, the viewer holds no frame at all.
PauseErases == (OwnPauser /\ auth \in {"paused", "takeover"}) => frame = "none"

\* A connection that went silent is dropped, so the stream reconnects.
StalledStreamDropped == (curl = "running" /\ conn = "stalled") ~> (curl # "running")

\* Closing the panel ends curl.
CaptureEndsWhenHidden == (~visible) ~> (curl = "none" \/ visible)

=============================================================================
