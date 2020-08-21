#!/bin/bash

## Default settings ##
sname="$(basename -- $0)"                                   # Script name
snamenoext="$(echo "$sname" | rev | cut -d'.' -f2- | rev)"  # Script name without the extension
spath="$(realpath "$0")"                                    # Script path
sdir="$(dirname "$spath")"                                  # Script directory
socketdir="$sdir/sockets"                                   # Directory to store tmux sockets
sessionname=''                                              # Custom socket name
log="$sdir/$(echo $sname|rev|cut -d. -f2-|rev).log"         # Log file
logmaxsize=1000                                             # Max number of lines to keep in the log
restartdelay=10                                             # For watchdog countdown
runfile=''                                                  # File to run using this script
argfile=''                                                  # File to pull args from
dashes=false                                                # Use with --arg-file to add dashes in front of every argument pulled from the argfile
open=false                                                  # Use this to open the session after creating it
isinrunfile=false                                           # Flag for internal use, to know when the script was executed from a run-file
logvars='$time'                                             # This is for the help page, don't forget to update it if you change the exposed variables in readrunfile()
timeformat='%F %T'                                          # Timestamp format
argnum="$#"                                                 # Number of arguments to parse, don't touch this if you don't know what you're doing

## Methods ##

function parseflags { # parse flags and return how many arguments were consumed
  while true; do
    case "$1" in
      -m|--max-log-size)        logmaxsize=$2;                    shift;;
      -l|--log)                 log="$(realpath "$2")";           shift;;
      -s|--socket-dir)          socketdir="$(realpath "$2")";     shift;;
      -n|--session-name)        sessionname="$2";                 shift;;
      -w|--restart-delay)       restartdelay=$2;                  shift;;
      -r|--run-file)            runfile="$(realpath "$2")";       shift;;
      -a|--arg-file)            argfile="$(realpath "$2")";       shift;;
      -d|--dashes)              dashes=true;;
      -o|--open)                open=true;;
      ---runfile---)            isinrunfile=true;;
      *)
        ((argnum=$argnum-$#))
        return
    esac
    shift
  done
}

function getflagstr {
  echo "-m $logmaxsize -l $log -s $socketdir -w $restartdelay$([ -n "$sessionname" ] && echo " -n $sessionname")$([ -n "$argfile" ] && echo " -a $argfile")$($dashes && echo " -d")"
}

function prepfiles {  # prepare dirs/files and check perms
  # prepare directories
  for d in $(echo -e "$socketdir"); do
    mkdir -p "$d" &> /dev/null  # mkdir if it doesn't exist (including parent dirs)
    if ! [ -d "$d" ]; then
      echo "Can't create directory: $d"
      exit 2
    fi
    chmod 775 "$d" &> /dev/null
    if [ $(stat -c '%a' "$d") != "775" ]; then  # if dir perms not 775
      echo "Can't set directory permissions: $d"
      exit 2
    elif ! [ -w "$d" ]; then
      echo "No permission to create files in directory: $d"
      exit 2
    fi
  done
  # check if files exist & have read perms
  for f in $(echo -e "$runfile\n$argfile"); do
    if [ -n "$f" ]; then    # if option not empty
      if [ -f "$f" ]; then
        if ! [ -r "$f" ]; then
          echo "No permission to read file: $f"
          exit 2
        fi
      else
        echo "File does not exist: $f"
        exit 2
      fi
    fi
  done
  # cleanup unused sockets
  for s in $socketdir/*; do # for each item in $socketdir
    [ -S "$s" ] &&
      [ -z "$(hassession "$s")" ] &&
        rm "$s"
  done
  # prepare log
  touch $log &> /dev/null
  if ! [ -f "$log" ]; then
    echo "Can't create log file: $log"
    exit 2
  elif ! [ -r "$log" ]; then
    echo "No permission to read log file: $log"
    exit 2
  elif ! [ -w "$log" ]; then
    echo "No permission to write to log file: $log"
    exit 2
  fi
  # prep script file
  chmod +x "$spath" &> /dev/null
  if ! [ -x "$spath" ]; then
    echo "Can't make script executable: $spath"
    exit 2
  fi
}

function rmdoc { # read file, print without comments & empty lines, 1: file to read
  sed 's/#.*//g;/^\s*$/d' "$1" # remove comments -> remove empty lines
}

function readrunfile { # reads file and replaces given variables with their values, 1: filename
  # You can set the variables that get exposed to run-files here, if you change this, don't forget to update $logvars at the top of this script
  rmdoc "$1"|\
  time=$(date)\
  envsubst
}

function filetoargs { # reads file, optionally adds dashes in front of each line and then prints the result as one line, with each entry separated by a space character. Ignores empty lines and #comments
  echo $(rmdoc $1|($dashes && sed 's/^/-&/g' || cat)) # read file skipping comments/empty lines -> (add dashes) -> make it a single line
}

function hassession {
  echo "$(tmux -S "$@" ls 2> /dev/null)"
}

function rightpadded { # print single-line string with space padding, 1: full width, 2: string
  local padding
  padding=$(printf '%*s' $(($1-$(echo -e "$2"|tr -d "\n\r"|wc -m))))
  echo -en "$2$padding"
}

function f {  # format text, 1: format, 2-*: text/parameters
  local normal format colored
  case "$1" in
    command) echo -en "$(f 4 $2) [$(f 1 'flags')] $3\n\t\t $(f 2 $4)";;
    flag) echo -en "\t$2 $(f 1 $3)\n\t\t$([ -z "$4" ] || echo -en "$(f 2 "Available in:") $(f 4 "$4")\n\t\t")$(f 2 "$5$([ -z "$6" ] || echo "\n\t\tDefault: $6")")";;
    note) echo -en "\t$(f 4 '-') $(f 2 "$2")";;
    *)
      normal=$(echo -en "\e[0m")
      format=$(
          case "$1" in
            1) echo -en "\e[4m\e[96m";; # underline & make light cyan
            2) echo -en "\e[93m";;      # make light yellow
            3) echo -en "\e[95m";;      # make light magenta
            4) echo -en "\e[92m";;      # make light green
          esac
        )
      case "$1" in
        1|4) colored="$(echo -ne "${@:2}"|sed "s/\W/$normal&$format/g;s/[-:]/$format&$normal/g")";; # when in one of these modes, only color alphanumeric, dashes and colons
        *) colored="$(echo -ne "${@:2}")" # color everything for the other modes
      esac
      echo -ne "$format$colored$normal"
  esac
}

function installautocomplete {
  local acscript
  acscript='
    function _serverboottoolacw_list {
      local w
      w=$('"$snamenoext"' list)
      [ $? -eq 0 ] && echo $w
    }

    function _serverboottoolacw_com {
      echo "log mksession watchdog start addcron install open kill list help"
    }

    function _serverboottoolacw {
      local cur prev opts
      COMPREPLY=()
      cur="${COMP_WORDS[COMP_CWORD]}"
      prev="${COMP_WORDS[COMP_CWORD-1]}"
      case "$prev" in
        open|kill)        opts=$(_serverboottoolacw_list);;
        '"$snamenoext"')  opts=$(_serverboottoolacw_com);;
        *) opts=''
      esac
      COMPREPLY=( $(compgen -W "$opts" -- $cur) )
    }

    complete -F _serverboottoolacw '"$snamenoext"
  echo "$acscript" > "/etc/bash_completion.d/$snamenoext"                 # Autocomplete script path
  echo "$acscript" > "/usr/share/bash-completion/completions/$snamenoext" # Autocomplete script path
  apt install bash-completion &&
  echo "Autocompletion script installed! Please restart your session to load it." ||
  (echo "Couldn't install bash-completion, autocomplete will be unavailable."; return 7)
}

function openflag{  # open session if the flag was provided & we're not in a run-file
  $isinrunfile || (
    $open &&
      open "$1"
  )
}

## Exposed methods ##

function mksession { # execute a command in a tmux session made by a specified user, 1: system user to run tmux as / name of tmux socket & session, 2: system group that can access the tmux socket, 3-*: command to run in the tmux session
  [ -z "$sessionname" ] && sessionname="$1"
  if [ -S "$socketdir/$sessionname" ]; then # socket exists
    if [ -n "$(hassession "$socketdir/$sessionname")" ]; then  # session already running on socket
      echo "This socket already has a running session, skipping: $1"
      openflag "$sessionname"
      return 1
    fi
  fi
  chgrp $1 "$socketdir"     # give user $1 temporary permission to create files in $socketdir
  sudo -iu $1 tmux -S "$socketdir/$sessionname" new -n $sessionname -d -s $sessionname ${@:3}  # start tmux session as user $1
  chgrp $2 "$socketdir/$sessionname"  # grant group $2 access to tmux session
  chgrp 0 "$socketdir"      # revoke temp perms
  echo "Started session: $sessionname"
  openflag "$sessionname"
}

function watchdog { # executes a command (args), re-executes it when the process exits, after a countdown
  trap '' SIGINT # ignore ctrl+c (does not affect children)
  local i key
  i=$restartdelay

  while true; do
  	rightpadded $(seq $restartdelay -1 $i|wc -m) "\rStarting up..." # overwrite current line
    echo -e "\n"
    sleep .2
    $1 $([ -n "$argfile" ] && echo $(filetoargs "$argfile")) ${@:2} # load argfile & run child process
    echo -e "\n\nProcess stopped! ($(date +"$timeformat") | exit code: $?)\nRestarting in $restartdelay seconds.\n\nPress any key to abort the restart..."
  	for i in $(seq $restartdelay -1 1); do # when the child process stops, count down and restart
    	if read -rs -n1 -t1 -p "$i "; then # if button pressed
        rightpadded $(seq $restartdelay -1 $i|wc -m) "\rExecution halted!" # overwrite current line
        echo -e "\n"
        sleep .3
        echo -en "Press C to continue process execution.\nPress T to terminate watchdog execution."
        key=''
        while [ "$key" != "c" ]; do
          read -rs -n1 key
          if [ "$key" == "t" ]; then
            echo -e '\n\nWatchdog shutting down...'
            exit 0
          fi
        done
        echo '' # $key == "c"
        break
      fi
  	done
  done
}

function log {  # write to log
  local temp
  echo "$@" >> "$log"
  temp=$(tail -n $logmaxsize "$log")
  echo "$temp" > "$log" # trim log
}

function start { # 1: system user to run as, 2: system group that can access the tmux socket, 3-*: executable/command
  local temprunfile line command args
  if [ -z "$runfile" ]; then
    mksession $1 $2 $spath watchdog $(getflagstr) ${@:3}
  else
    temprunfile=$(echo "$runfile")
    runfile=''
    readrunfile "$temprunfile"|\
    while read line; do # exec each line & forward sensible settings
      line="$(echo "$line"|tr "\t" ' '|tr -s ' ')" # squeeze spaces
      command="$(echo "$line"|cut -d' ' -f1)"
      args="$(echo "$line"|cut -d' ' -f2-)"
      $spath $command ---runfile--- $(getflagstr) $args
    done
  fi
}

function addcron {
  local before
  if [ -n "$1" ]; then
    before=$(crontab -l)
    (crontab -l|grep -v -F "$sname"; echo "### Added by $sname ###"; echo "@reboot '$spath' start -r '$(realpath "$1")'") | crontab - && \
    echo -e "Cron job added!\nDiff (before - after):\n" && \
    diff -y <(echo "$before") <(crontab -l)
  else
    echo "No run-file specified."
    exit 5
  fi
}

function install {
  local compath
  echo "Adding command..."
  compath="/usr/bin/$snamenoext"
  ln -fs "$spath" "$compath"
  which "$snamenoext" > /dev/null && (
  echo -e "Command added successfully!\n$snamenoext: $compath -> $spath\nInstalling autocompletion script..."
  installautocomplete
  ) ||
  echo "Failed to add command."
}

function open {
  if [ -e "$socketdir/$1" ]; then
    if [ -n "$(hassession "$socketdir/$1")" ]; then  # session already running on socket
      tmux -S "$socketdir/$1" attach
    else
      echo "This socket does not have a running session: $1"
      exit 4
    fi
  else
    echo "Socket not found: $1"
    exit 4
  fi
}

function kill {
  if [ -e "$socketdir/$1" ]; then
    tmux -S "$socketdir/$1" kill-session &&
    echo "Sent kill signal: $1"
  else
    echo "Socket not found: $1"
    exit 6
  fi
}

function list {
  local flag
  flag=false
  for s in $socketdir/*; do # for each item in $socketdir
    if [ -S "$s" ]; then
      if [ -n "$(hassession "$s")" ]; then
        echo "$(basename -- $s)"
        flag=true
      fi
    fi
  done
  $flag || (echo "No running sessions found."; return 6)
}

function phelp { # print help message
  local p
  case "$1" in
    log)        p=$(f command $1  "$(f 1 'text')"                                             "Write something in the log file. This is mostly useful in a \"run-file\", ran with the start command. Supports these variables: $logvars");; # TODO: add that it's useful with run-files
    mksession)  p=$(f command $1  "$(f 1 'system-user system-group shell-command')"           "Execute a command in a tmux session made by a specified user. The tmux socket can be accessed by any user that belongs to the specified group.");;
    watchdog)   p=$(f command $1  "$(f 1 'shell-command')"                                    "Execute a command and re-execute it if the process exits, after a countdown");;
    start)      p=$(f command $1  "(-r $(f 1 'file|system-user system-group shell-command'))" "Execute a command in a tmux session made by a specified user, which is accessible by users in the specified group and re-execute the command if the process exits. This essentially combines the commands mksession & watchdog.");;
    addcron)    p=$(f command $1  "$(f 1 'run-file')"                                         "Makes the script run automatically on startup. The script will run with the options \"start --run-file\", so you'll need to provide a run-file. If you already manually added cron jobs for this script, don't use this command.");;
    install) p=$(f command $1  "$(f 1)"                                                       "Adds the script as a system command and adds autocompletion. This will make a symlink, so make sure the script is located where you want it to be, before running this.");;
    open)       p=$(f command $1  "$(f 1 'session-name')"                                     "Connect to a shared tmux session. Essentially an alias for \"tmux attach\", with a different default socket directory.");;
    kill)       p=$(f command $1  "$(f 1 'session-name')"                                     "Kill a shared tmux session. Essentially an alias for \"tmux kill-session\", with a different default socket directory.");;
    list)       p=$(f command $1  ""                                                          "List running sessions. Please note that This will only list sessions you have access to.");;
    commands)   p="$(f 3 'Script commands:')\n"
                for a in log mksession watchdog start addcron install open kill list; do p+="\t$(phelp $a)\n\n"; done;;
    flags)      p="$(f 3 'Flags:')\n"
                p+="$(f flag  "-h, --help, help"    "[script-command]"  ""                              "Display this help message, or get info on the provided script command and exit."       "")\n\n"
                p+="$(f flag  "-m, --max-log-size"  "size"              "start, log"                    "Max log size, if exceded, older records will be deleted to maintain."                  "$logmaxsize")\n\n"
                p+="$(f flag  "-l, --log"           "file"              "start, log"                    "Log file path."                                                                        "$log")\n\n"
                p+="$(f flag  "-s, --socket-dir"    "directory"         "start, mksession, open, kill"  "Directory to store tmux sockets in."                                                   "$socketdir")\n\n"
                p+="$(f flag  "-n, --session-name"  "name"              "start, mksession"              "Custom socket name for your session."                                                  "same as the system user name for the session")\n\n"
                p+="$(f flag  "-w, --restart-delay" "seconds"           "start, watchdog"               "Wait this amount of time before restarting a dead process."                            "$restartdelay")\n\n"
                p+="$(f flag  "-r, --run-file"      "file"              "start"                         "Run the script commands in a file. Check the \"Notes\" section for more information."  "$runfile")\n\n"
                p+="$(f flag  "-a, --arg-file"      "file"              "start"                         "Read arguments from a file, append right after the given command."                     "$argfile")\n\n "
                p+="$(f flag  "-d, --dashes"        ""                  "start"                         "To be used with the -a flag. Add dashes in front of every argument."                   "$dashes")\n\n"
                p+="$(f flag  "-o, --open"          ""                  "start, mksession"              "Open the session right after creating it. Incompatible with -r & run-files!"           "$open")\n\n"
                ;;
    notes)      p="$(f 3 'Notes:')\n"
                p+="$(f note  "Run this script as root. This is to be able to start sessions as other users.")\n"
                p+="$(f note  "A great way to run this script is using a cron job that runs through root on startup. Using --run-file is a good way to keep things organized when doing this.")\n"
                p+="$(f note  "You can make a file that contains multiple commands for this script and run it with --run-file. The file needs to contain one command on each line. Lines starting with #, will be ignored. A command is essentially the arguments you would give the script if you were running it normally.\nExample:\n\"$sname log hello world\"\nis equivalent to\n\"echo log hello world > test ; $sname start --run-file test\"")\n"
                p+="$(f note  "Tmux might occasionally create files named \"tmux-*.log\" in the selected user's home directory. Feel free to delete them.")\n"
                ;;
    *)          p="$(f 3 'General usage:') $sname [-h] [$(f 1 'script-command') [$(f 1 'flags')] ($(f 1 'input')|$(f 1 'shell-command'))]\n\n"
                p+="$(phelp commands)\n\n"
                p+="$(phelp flags)\n\n"
                p+="$(phelp notes)"
  esac
  echo "$(echo -e "$p"|sed '${/^\s*$/d}')"
}

## Main ##

cmd="$1"          # grab args
parseflags ${@:2}
shift $argnum

if [ $(id -u) == 0 ]; then # if ran as root
  prepfiles
else
  case "$cmd" in
    log|mksession|start|addcron|install)  # only root can run these commands
      echo "Only root is allowed to run this command."
      exit 3;;
  esac
fi

case "$cmd" in  # exec command
  log|mksession|watchdog|start|addcron|install|open|kill|list) $cmd $@;;
  help|--help|-h|'')            phelp $@; exit 0;;
  *) echo "Unrecognized command, type: $sname --help"
  exit 1
esac
exit $?
