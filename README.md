# ServerBootTool
A bash script that helps automate starting up (and sharing the session of) programs that require a session to keep running.
Some common examples are game servers, like Minecraft or Garry's Mod, Node.js apps, etc.
The script uses tmux, so make sure to install that first.

With this script:
- You don't have to worry about having to keep the session open, so your app keeps running
- If your app closes/crashes, the script can make sure it starts back up after a countdown (abort-able)
- If you want to give other system users access to the session (ex. Minecraft console), you can do so, in a secure fashion and with less headaches
- If you want to make your apps start automatically with your server, you can do it with minimal knowledge
- You can use a single file to tell the script all the apps it has to run, so you don't have a bunch of scripts all over the place
- If an app requires a ton of arguments to run, you can keep things tidy, by having all your arguments for an app in a file, in separate lines and with comments, that you can feed to this script when you run the app with it (a good example is running a java app that you want to really tune the JVM for)
- If you use an argument file, it will be reloaded, if your app gets restarted by the watchdog
- By default, each app gets executed as a separate regular system user, to maximize security (each session gets named after the user, but you can use custom names to run multiple sessions as the same user)
- You only need to download the script itself, it will create files/directories as needed
- You get sub-command & session name autocomplete (for the sessions your user has access to)

## How to use
The script has a help command you can take a look at for more info, but here's an example that shows how you'd set it up to run two Minecraft servers and a Node.js app on startup and how to share the sessions with other system users. Don't blindly copy things from the example, since some things are there just for demonstration purposes.

- First, we have to make a system user for each app and install it as that user, in their home directory (or similar).
For this example, we'll name the users "mcserver1", "mcserver2" & "nodeapp".
- We'll also make some groups (optional), that will grant their members access to each session: "mcserver1-admin", "mcserver2-admin" & "nodeapp-admin".
- For this example, we'll presume that we want to give each Minecraft server a bunch of arguments. To keep things neat, we'll make a file "/home/mcserver1/jvmargs":
```bash
## Memory management ##
Xms2G
Xmx2G
Xmn600M

### For FML ###
#Dfml.queryResult=confirm

## Server configuration ##
jar forge-1.10.2-12.18.3.2511-universal.jar
o true
server
Djava.net.preferIPv4Stack=true
```
and a second file "/home/mcserver2/jvmargs":
```bash
## Memory management ##
Xms1G
Xmx1G
Xmn330M

## Server configuration ##
jar spigot-1.13.2.jar
o true
```
- Then we'll put this script in the directory we want it to be, for this example we'll use "/startscript/serverboottool.sh".
- Now we can make a file that tells the script what to run on startup and how. Lets name it "testrun" and put it in the same directory as the script:
```bash
log Startup: $time

## Node.js ##
start nodeapp nodeapp-admin node /home/nodeapp/server.js

## Minecraft ##
start -d -a /home/mcserver1/jvmargs mcserver1 mcserver1-admin java nogui
start -d -a /home/mcserver2/jvmargs mcserver2 mcserver2-admin java nogui
```
###### Quick explanation of the files
>- "log Startup: $time" is completely optional. All it does, is write the date and time the script was ran in a log file.
>- The Node.js part, means: start the app as the user "nodeapp", give access to the members of the group "nodeapp-admin" and run the shell command "node /home/nodeapp/server.js"
>- The Minecraft servers will have some extra arguments, that we want to load from the files named "jvmargs" accordingly. That's what the "-a /home/mcserver*/jvmargs" part is for. Note that the arguments loaded from the file will be put right after "java", so if you want extra arguments stated in the "testrun" file, you can put them right after, like with "nogui".
>- The "-d", is optional, but it tells the script to put a dash in front of each argument it loads from the "jvmargs" file. That's just to make the "jvmargs" file more pleasing to the eye, but it's also personal preference. Every argument we have in that file will need a dash in front of it, so we can use "-d" here. This only applies to the file's arguments, not any extra ones, like "nogui".
>- Anything starting with # in the "jvmargs" files will be ignored, this is nice for comments and temporarily disabling arguments.
>- For example, in the case of "mcserver1", what the script will essentially run, is: "**java** *-Xms2G -Xmx2G -Xmn600M -jar forge-1.10.2-12.18.3.2511-universal.jar -o true -server -Djava.net.preferIPv4Stack=true* **nogui**"

- We can now start everything by entering the command: "sudo /startscript/serverboottool.sh start --run-file /startscript/testrun"
- Finally, we can make it get executed on startup, by entering: "sudo /startscript/serverboottool.sh addcron /startscript/testrun"
- Everything is running, but to connect to a session, we need to be part of its group. For example, to connect to the "noteapp" session, we need to be part of the system group "nodeapp-admin", as stated in "testrun".
- After we become a member of the group, we can connect with "/startscript/serverboottool.sh open nodeapp".
- We can share the session with more users by just adding them to the group.
- If you don't want to share the session with anyone (except the app's user and root), just set the group in the "testrun" file to be the same as the username (ex.: "nodeapp").
- The script uses tmux to make the sessions, so to learn how to disconnect from a session, etc, check tmux's manual.
- For more usage information, enter: "/startscript/serverboottool.sh help"
