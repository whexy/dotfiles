# Alfred workflow: the keyword `rex` lists the hosts Rex is connected to, and
# Enter opens a new session on the selected one.
{ lib, runCommand }:
let
  hosts = "5C6E1F0A-3B2D-4E8F-9A71-0D4C2B6E8F13";
  newSession = "A2B9D4E7-6C1F-4A3B-8E5D-7F0C9B1A2D46";

  info = {
    bundleid = "dotfiles.rex";
    name = "Rex";
    description = "New Rex session on a connected host";
    category = "Tools";
    createdby = "dotfiles";
    readme = "";
    webaddress = "";
    objects = [
      {
        uid = hosts;
        type = "alfred.workflow.input.scriptfilter";
        version = 3;
        config = {
          keyword = "rex";
          withspace = true;
          title = "Rex";
          subtext = "New session on a host Rex is connected to";
          runningsubtext = "Asking Rex for its hosts…";
          # External script: Alfred runs `scriptfile` by its shebang.
          type = 8;
          scriptfile = "hosts.js";
          script = "";
          scriptargtype = 1;
          escaping = 102;
          # Optional argument, filtered by Alfred: the script runs once per
          # invocation rather than once per keystroke.
          argumenttype = 1;
          argumenttreatemptyqueryasnil = true;
          argumenttrimmode = 0;
          alfredfiltersresults = true;
          alfredfiltersresultsmatchmode = 0;
          queuemode = 1;
          queuedelaymode = 0;
          queuedelaycustom = 3;
          queuedelayimmediatelyinitially = true;
        };
      }
      {
        uid = newSession;
        type = "alfred.workflow.action.script";
        version = 2;
        config = {
          type = 8;
          scriptfile = "new-session.js";
          script = "";
          scriptargtype = 1;
          escaping = 102;
          concurrently = false;
        };
      }
    ];
    connections.${hosts} = [
      {
        destinationuid = newSession;
        modifiers = 0;
        modifiersubtext = "";
        vitoclose = false;
      }
    ];
    uidata = {
      ${hosts} = {
        xpos = 50;
        ypos = 50;
      };
      ${newSession} = {
        xpos = 250;
        ypos = 50;
      };
    };
  };
in
runCommand "alfred-workflow-rex"
  {
    plist = lib.generators.toPlist { escape = true; } info;
    passAsFile = [ "plist" ];
  }
  ''
    mkdir $out
    cp "$plistPath" $out/info.plist
    install -m755 ${./hosts.js} $out/hosts.js
    install -m755 ${./new-session.js} $out/new-session.js
  ''
