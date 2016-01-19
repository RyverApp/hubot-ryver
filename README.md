# Hubot for Ryver (general instruction for Linux\OSX)


## Notes
Hubot-Ryver is in beta


## Prequisites:
* [nodejs](https://nodejs.org)
* [npm](https://www.npmjs.com)
	
	
## Installation:
1. Install the hubot generator:
	
    ````npm install -g yo generator-hubot````
	
1. Create base installation directory: 
	
	````
    mkdir -p /var/www/hubot
	cd hubot
    ````

1. Run installation:

	````yo hubot --adapter ryver````
	
1. Create startup script with relevant adapater\hubot configuration (see below) OR run:

	````./bin.hubot````
	
	
## Hubot-Ryver behavior:
Hubot-Ryver behaves the same across 1:1, Team, and Forum chats.  The bot user will need to have access
to the Team\Forum.  Hubot will auto-join teams\forums on startup and should detect when it is
added\removed from an existing or new Team\Forum.
	
 
## Ryver Adapter Configuration
	
### HUBOT_RYVER_USERNAME
The string 'username' of the account Hubot should connect with
		
### HUBOT_RYVER_PASSWORD
The string 'password' of the account Hubot should connect with
			
### HUBOT_RYVER_APP_URL
This is the url of your Ryver app.  For example: mycoolapp.ryver.com
    		
### HUBOT_RYVER_USE_SSL
Whether or not to use ssl for the connection.  You should only disable for testing.
````
Valid values: yes | no
Default: yes
````

### HUBOT_RYVER_JOIN_FORUMS
Whether or not hubot should auto-join to available Forums
````
Valid values: yes | no
Default: yes
````
    	    		  	    		
## Useful Hubot COnfiguration
	
### HUBOT_LOG_LEVEL
Set log verbositiy ('debug')
	
### HUBOT_NAME
The name of your bot.  Used for @mention parsing
		
### PORT
The port hubot should listen on (http server)
		
### HUBOT_IP
The interface hubot should bind to
		
		
## Startup Script Examples:

### Ubuntu:
````
description "Hubot Ryver"
#Assumes an installation at /var/www/hubot with permissions given to a www-data user

env PORT='5556'
env HUBOT_IP='10.1.255.10'
env HUBOT_NAME='hubot'
env HUBOT_LOG_LEVEL='debug'
env HUBOT_RYVER_USERNAME='user'
env HUBOT_RYVER_PASSWORD='password'
env HUBOT_RYVER_APP_URL='mycoolapp.ryver.com
env HUBOT_RYVER_JOIN_FORUMS='no'

start on filesystem or runlevel [2345]
stop on runlevel [!2345]
		
chdir /var/www/hubot
		
#Automatically Respawn:
respawn
respawn limit 10 5
		
exec su -c "bin/hubot -l 'hubot' 2>&1 | logger -t hubot-ryver_service" www-data
````		
			
		