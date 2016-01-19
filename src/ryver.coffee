{Adapter, EnterMessage, LeaveMessage, TextMessage} = require('hubot')
Ratatoskr             = require('ratatoskr')
HTTP                  = require 'http'
HTTPS                 = require 'https'

class RyverBot extends Adapter

  constructor: (@robot) ->

    #all instance vars have corresponding getter and setter functions
    @options = null
    @sessionId = null
    @jid = null
    @chatUrl = null
    @joinedRooms = []
    @client = null
    @connected = false
    @forumIdMap = []
    @forumJidMap = []
    @teamIdMap = []
    @userIdMap = []

    super @robot

  # Private: Get configuration info from the Ryver apis before connecting
  #
  # Return nothing
  bootstrap: (callback) ->
    @post '/api/1/odata.svc/User.Login()', null, (resp, data) =>
      #@robot.logger.debug(JSON.stringify(data))
      @setSessionId data.d.sessionId
      @setChatUrl data.d.services.chat

      @initRyverInfo callback

  # Private: Fetches and sets RyverInfo and performs brain loading
  #
  # Return nothing
  initRyverInfo: (callback) ->
    @get '/api/1/odata.svc/Ryver.Info', (resp, info) =>
      #@robot.logger.debug JSON.stringify(info)
      @setJid info.d.me.jid
      @buildForumMap info
      @buildTeamMap info
      @buildUserMap info
      @buildBrainFromInfo info

      if callback
        callback()

  # Private: Join all teams\forums we are a member of
  #
  # info - blob from Ryver.Info
  #
  # Return nothing
  joinBotRooms: =>
    for k, jid of @forumIdMap
      @joinForum jid

    for k, jid of @teamIdMap
      @joinTeam jid

    return null

  # Private: Load all users into the brain
  #
  # info - blob from Ryver.Info
  #
  # Return nothing
  buildBrainFromInfo: (info) ->
    for user in info.d.users
      @addUser user.jid, user.username, user.descriptor

    @robot.brain.save()
    return null

  # Private: Add a user to hubot brain
  #
  # jid - string
  # username - string
  # realName - string
  # room - string (optional)
  #
  # Return nothing
  addUser: (jid, username, realName, room = null) ->
    options = {
      name: username
      real_name: realName
      room: room
    }
    @robot.logger.debug "Adding #{jid} with #{JSON.stringify options} to brain"
    @robot.brain.userForId jid, options

  # Private: Add lookup record for a user to map
  #
  # id - int
  # jid - string
  #
  # Return nothing
  addToUserMap: (id, jid) ->
    @robot.logger.debug "Added to user id map id:#{id} jid:#{jid}"
    @getUserMap()[id] = jid

  # Private: Add lookup records for a forum to map
  #
  # id - int
  # jid - string
  #
  # Return nothing
  addToForumMap: (id, jid) ->
    @robot.logger.debug "Added to forum map id:#{id} jid:#{jid}"
    @getForumIdMap()[id] = jid
    @getForumJidMap()[jid] = id

  # Private: Add lookup records for a team to map
  #
  # id - int
  # jid - string
  #
  # Return nothing
  addToTeamMap: (id, jid) ->
    @robot.logger.debug "Added to team map id:#{id} jid:#{jid}"
    @getTeamMap()[id] = jid

  # Private: Builds Team lookup map from Ryver.Info result
  #
  # info - array
  #
  # Return nothing
  buildTeamMap: (info) ->
    for team in info.d.teams
      @addToTeamMap team.id, team.jid

    return null

  # Private: Builds Forum lookup maps from Ryver.Info result
  #
  # info - array
  #
  # Return nothing
  buildForumMap: (info) ->
    for forum in info.d.forums
      @addToForumMap forum.id, forum.jid

    return null

  # Private: Builds User lookup maps from Ryver.Info result
  #
  # info - array
  #
  # Return nothing
  buildUserMap: (info) ->
    for user in info.d.users
      @userIdMap[user.id] = user.jid

    return null

  # Public: Extended Adapter method for invoking the bot to run
  #
  # Returns nothing.
  run: ->
    @bootstrap => @connect()

  # Private: GET Helper
  #
  # Returns data to callback
  get: (path, callback) ->
    @request "GET", path, null, callback

  # Private: POST Helper
  #
  # Returns data to callback
  post: (path, body, callback) ->
    @request "POST", path, body, callback

  # Private: perform http requests.  Mimics campfire adapter
  #
  # method - GET | POST | PUT ...etc
  # path - the application endpoint
  # body - struct to include as body
  # callback - (optional)
  #
  # Returns response
  request: (method, path, body, callback) ->
    logger = @robot.logger

    options = @getOptions()
    username = options.username
    password = options.password
    host = options.appUrl
    ssl = options.useSSL

    web = HTTPS
    if ssl == 'no'
      web = HTTP

    headers =
      'Accept'        : 'application/json'
      "Host"          : host
      "Content-Type"  : "application/json"
      "User-Agent"    : "Hubot/#{@robot?.version} (#{@robot?.name})"

    reqOptions =
      "agent"  : false
      "auth"   : "#{username}:#{password}"
      "host"   : host
      "path"   : path
      "method" : method
      "headers": headers

    if method is "POST" || method is "PUT"
      if typeof(body) isnt "string"
        body = JSON.stringify body

      body = new Buffer(body)
      reqOptions.headers["Content-Length"] = body.length

    req = web.request reqOptions, (response) ->
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", ->
        if response.statusCode >= 400
          switch response.statusCode
            when 401
              throw new Error "Invalid credentials"
            else
              logger.error "Ryver status code: #{response.statusCode}"
              logger.error "Ryver response data: #{data}"

        if callback
          try
            callback response, JSON.parse data
          catch error
            callback response, data or {}

      response.on "error", (err) ->
        logger.error "Ryver response error: #{err}"
        callback err, {}

    if method is "POST" || method is "PUT"
      req.end(body, 'binary')
    else
      req.end()

    req.on "error", (err) ->
      logger.error "Ryver request error: #{err}"

  # Private - method to help log events
  #
  # name - the name of the event
  # items... - array of items passed in on callback
  #
  # Returns Nothing
  eventLogger: (name, items...) =>
    @robot.logger.debug "hubot-ryver - #{name}: #{JSON.stringify items}"
    return null

  # Private - callback handler after authentication occurs
  #
  # ack - the ack payload
  #
  # Returns Nothing
  handleAuthenticated: (ack) =>
    if "error" of ack
      @robot.logger.error "Failed auth to server ack:#{JSON.stringify ack}"

      if ack.error.code is "auth_failed"
        #Try to renew credentials and recover
        @run()

      return null

    @robot.logger.debug "authenticated: #{JSON.stringify ack}"

    if not @getConnected()
      #We've never connected before in this runtime.
      #Load scripts and start available loop
      @startAvailables()
      @setConnected true
      @emit 'connected'
    else
      #We're reauthenticating from a disconnect.
      #Send available immediately (don't wait for loop)
      @sendAvailable()

    #load our teams\forums
    @initRyverInfo(=> @joinBotRooms())

    return null

  # Private - callback handler when a chat is received from the client
  #
  # message - the message payload
  #
  # Returns Nothing
  handleChat: (message) =>
    if message.to is @getJid()
      type = 'chat'
      user = @getUserFromJid message.from
    else
      type = 'groupchat'

      #don't process groupchats from ourselve
      if message.from is @getJid() then return null

      user = @getUserFromJid message.from, message.to

    @robot.logger.debug "Received #{type} '#{message.text}'"
    @receive new TextMessage user, message.text, message.key
    return null

  # Private - callback handler when the client begins connecting to the server
  #
  # Returns Nothing
  handleConnecting: =>
    @robot.logger.info "Connecting to Ryver..."
    @leaveRoom()
    return null

  # Private - Router for different event topics
  #
  # message - struct
  #
  # Return Nothing
  handleEvent: (message) =>
    if message.topic is '/api/ryver_info/changed'
      @handleEventChanged(message)
    else if message.topic is '/api/notify'
      @handleEventNotify(message)

    return null

  # Private - Router for notify events
  #
  # message - struct
  #
  # Returns Nothing
  handleEventNotify: (message) =>
    if message.data.predicate is 'chat_mention'
      @handleChatMentioned(messsage)

  # Private - Router for change events
  #
  # message - struct
  #
  # Returns Nothing
  handleEventChanged: (message) =>
    for d in message.data
      if d.type is 'user_created'
        @handleUserCreated(d)
      else if d.type in ['forum_member_created', 'team_member_created']
        @handleMemberCreated(d)
      else if d.type in ['forum_member_deleted', 'team_member_deleted']
        @handleMemberDeleted(d)
      else if d.type is 'forum_created'
        @handleForumCreated(d)
      else if d.type is 'team_created'
        @handleTeamCreated(d)

  # Private - handle member created events that are published
  #
  # data - struct
  #
  # Returns Nothing
  handleMemberCreated: (data) =>
    userJid
    if d.type is 'forum_member_created'
      userJid = @getUserJid d.forum_member.user.id
    if d.type is 'team_member_created'
      userJid = @getUserJid d.team_member.user.id

    if userJid is @getJid()
      if d.type is 'team_member_created'
        #We may not know about this team.
        #Could be added after it was created or was offline when created
        @initRyverInfo => @joinTeam @getTeamJid(d.team_member.team.id)
    else
      if d.type is 'forum_member_created'
        roomJid = @getForumJid d.forum_member.forum.id
        userId = d.forum_member.user.id
      if d.type is 'team_member_created'
        roomJid = @getTeamJid d.team_member.team.id
        userId = d.team_member.user.id

      user = @getUserFromJid(userJid, roomJid)
      @robot.logger.debug "#{user.name} has been added to #{roomJid}"
      @receive new EnterMessage user

  # Private - handle member deleted events that are published
  #
  # data - struct
  #
  # Returns Nothing
  handleMemberDeleted: (data) =>
    if d.type is 'forum_member_deleted'
      roomJid = @getForumJid d.forum_member.forum.id
    if d.type is 'team_member_deleted'
      roomJid = @getTeamJid d.team_member.team.id

    userJid = @getUserJid d.team_member.user.id
    if userJid is @getJid()
      @leaveRoom roomJid
    else
      user = @getUserFromJid userJid, roomJid
      user.room = roomJid
      @robot.logger.debug "#{user.name} has been removed from #{roomJid}"
      @receive new LeaveMessage user

  # Private - handle user created events that are published
  #
  # data - struct
  #
  # Returns Nothing
  handleUserCreated: (data) =>
    @addUser d.user.jid, d.user.username, d.user.descriptor
    @addToUserMap d.user.id, d.user.jid

  # Private - handle forum created events that are published
  #
  # data - struct
  #
  # Returns Nothing
  handleForumCreated: (data) =>
    #We don't know about this room so make sure to add it to the map
    @addToForumMap d.forum.id, d.forum.jid
    @joinForum d.forum.jid

  # Private - handle team created events that are published
  #
  # data - struct
  #
  # Returns Nothing
  handleTeamCreated: (data) =>
    #We don't know about this room so make sure to add it to the map
    @addToTeamMap d.team.id, d.team.jid

  # Private - handle chat mention events that are published
  #
  # message - struct
  #
  # Returns Nothing
  handleChatMentioned: (message) =>
    jid = message.data.via.workroom.jid
    if @isJoinedToRoom(jid) then return

    envelop = {
      from: message.data.via.fromUser.jid
      to: message.data.via.workroom.jid
      text: message.data.via.__descriptor
      key: message.data.via.id
    }

    roomType = message.data.via.workroom.__metadata.type
    if roomType is 'Entity.Forum'
      @joinForum jid, => @handleChat(envelop)
    else
      @joinTeam jid, => @handleChat(envelop)

  # Private - helper to check if we are already joined to a room
  #
  # room - the room jid
  #
  # Return Nothing
  isJoinedToRoom: (room) ->
    if room in @joinedRooms then true else false

  # Private - send a join message to a room
  #
  # room - the room jid
  #
  # Return Nothing
  joinRoom: (jid, callback) ->
    @getClient().sendTeamJoin {to: jid}
    @joinedRooms.push jid unless jid in @joinedRooms

    if callback
      callback()

    return null

  # Private
  #
  # jid - the team jid
  #
  # Return Nothing
  joinTeam: (jid, callback) ->
    @robot.logger.debug "Joining team jid:#{jid}"
    @joinRoom jid, callback

  # Private: Handles joining a Forum.  Emits Team.Join() call and adds to map
  #
  # jid - string
  #
  # Returns nothing
  joinForum: (jid, callback) ->
    if @getOptions().joinForums is 'yes'
      @robot.logger.debug "Joining forum jid:#{jid}"
      forumId = @getForumId jid
      url = "/api/1/odata.svc/forums(#{forumId})/Team.Join()"
      @post url, null, (resp, data) =>
        @joinRoom jid, callback

  # Private - leave a room.  Can specify a specific room or omit to clear all
  #
  # room - the room jid (optional)
  #
  # Return Nothing
  leaveRoom: (room) ->
    @robot.logger.debug "Leaving room #{room}"
    if not room
      @joinedRooms = []
    else
      @joinedRooms = (x for x in array when x isnt room)
    return null

  # Private - Generates the appropriate User context based on room
  #
  # id - the jid of the user
  # room - the room jid (if applicable)
  #
  # Return User
  getUserFromJid: (jid, room = null) ->
    user = @robot.brain.userForId jid
    id = if room then [room, jid].join('/') else jid

    #Most users should be loaded on bootstrap.  However, it's possible
    #new users were added.  Default to jids
    options = {
      name: user.name or jid
      real_name: user.real_name or jid
      room: room
    }
    user = @robot.brain.userForId id, options
    @robot.logger.debug "Received #{JSON.stringify user}"
    return user

  # Private: method for getting the runtime options
  #
  # Returns a struct of key-value options
  getOptions: ->
    if not @options
      @setOptions()
    @options

  # Private: method for setting the runtime option
  #
  # Returns Nothing
  setOptions: ->
    @options =
      username: process.env.HUBOT_RYVER_USERNAME
      password: process.env.HUBOT_RYVER_PASSWORD
      appUrl: process.env.HUBOT_RYVER_APP_URL
      useSSL: process.env.HUBOT_RYVER_USE_SSL or 'yes'
      retries: 5
      availableFrequency: 300000 #every 5 minutes
      joinForums: process.env.HUBOT_RYVER_JOIN_FORUMS or 'yes'

    for optionKey of @options
      if not @options[optionKey]
        throw new Error "No env variable found for #{optionKey}"

    return null

  # Private: method for getting the connected instance variable
  #
  # Returns boolean
  getConnected: ->
    @connected

  # Private: method for setting the connected instance variable
  #
  # value - true | false
  #
  # Returns Nothing
  setConnected: (value) ->
    @connected = value

  # Private: method for getting the instantiated client
  #
  # Returns Client obj
  getClient: =>
    if not @client
      @setClient()
    @client

  # Private:
  #
  # Return <string>
  getSessionId: ->
    return @sessionId

  # Private:
  #
  # value - <string>
  #
  # Returns Nothing
  setSessionId: (value) ->
    @sessionId = value

  # Private:
  #
  # Return <string>
  getChatUrl: ->
    return @chatUrl

  # Private:
  #
  # value - <string>
  #
  # Returns Nothing
  setChatUrl: (value) ->
    @chatUrl = value

  # Private:
  #
  # Return <string>
  getJid: ->
    return @jid

  # Private:
  #
  # value - <string>
  #
  # Returns Nothing
  setJid: (value) ->
    @jid = value

  # Private:
  #
  # Return <array>
  getForumIdMap: ->
    return @forumIdMap

  # Private:
  #
  # Return <array>
  getForumJidMap: ->
    return @forumJidMap

  # Private:
  #
  # Return <array>
  getTeamMap: ->
    return @teamIdMap

  # Private:
  #
  # Return <array>
  getUserMap: ->
    return @userIdMap

  # Private:
  #
  # id - int
  #
  # Returns string
  getUserJid: (id) ->
    return @getUserMap()[id]

  # Private:
  #
  # id - int
  #
  # Returns string
  getForumJid: (id) ->
    return @getForumIdMap()[id]

  # Private:
  #
  # jid - string
  #
  # Returns int
  getForumId: (jid) ->
    return @getForumJidMap()[jid]

  # Private:
  #
  # id - int
  #
  # Returns string
  getTeamJid: (id) ->
    return @getTeamMap()[id]

  # Private: method for setting the client
  #
  # Returns Nothing
  setClient: =>
    options = @getOptions()

    @client = new Ratatoskr.Client({
      extensions: [
        Ratatoskr.resume({ping: 5 * 1000, retry: options.retries})
        Ratatoskr.presenceBatch()
      ]
    })

    #log all events
    @client.on 'authenticated', (items...) =>
      @eventLogger('authenticated', items...)
    @client.on 'chat', (items...) => @eventLogger('chat', items...)
    @client.on 'connecting', (items...) => @eventLogger('connecting', items...)
    @client.on 'disconnected', (items...) =>
      @eventLogger('disconnected', items...)
    @client.on 'event', (items...) => @eventLogger('event', items...)
    @client.on 'presence_change:batch', (items...) =>
      @eventLogger('presence_change:batch', items...)
    @client.on 'resume', (items...) => @eventLogger('resume', items...)
    @client.on 'resume:stop', (items...) =>
      @eventLogger('resume:stop', items...)
    @client.on 'resume:tick', (items...) =>
      @eventLogger('resume:tick', items...)
    @client.on 'resume:quit', (items...) =>
      @eventLogger('resume:quit', items...)
    @client.on 'team_join', (items...) => @eventLogger('team_join', items...)
    @client.on 'team_leave', (items...) => @eventLogger('team_leave', items...)
    @client.on 'user_typing', (items...) =>
      @eventLogger('user_typing', items...)

    #events with handlers
    @client.on 'authenticated', @handleAuthenticated
    @client.on 'chat', @handleChat
    @client.on 'connecting', @handleConnecting
    @client.on 'event', @handleEvent
    @client.on 'resume:quit', (items...) => @close()
    @client.on 'resume:stop', (items...) => @close()
    @client.on 'presence_change:batch', (items...) => @handlePresenceChange

  # Private: worker loop to periodically send 'available' probes to the server
  #
  # Returns Nothing
  startAvailables: =>
    @sendAvailable()
    setTimeout @startAvailables, @getOptions().availableFrequency

  # Private: helper to send an available stanza through the client
  sendAvailable: =>
    if @isClientConnected()
      @robot.logger.debug "Sending 'available' stanza"
      @getClient().sendPresenceChange {presence: 'available'}

  # Private: helper to check if the websocket client is connected
  #
  # Return boolean
  isClientConnected: ->
    return @client.status > Ratatoskr.ConnectionStatus.Connected

  # Private: connect with the client
  #
  # Returns Nothing
  connect: ->
    client = @getClient()
    client.resource = @getJid()
    client.agent = 'Ryver'
    client.authorization = "Session #{@getSessionId()}"
    client.endpoint = @getChatUrl()
    client.connect()
    return null

  # Private: disconnect with the client
  #
  # Returns Nothing
  disconnect: ->
    @getClient().disconnect()
    return null

  # Public: extended Adapter method to send a message
  #
  # envelope - A Object with message, room and user details.
  # messages  - One or more strings to send.
  #
  # Returns nothing
  send: (envelop, messages...) ->
    to = if envelop.room then envelop.room else envelop.user.id

    for msg in messages
      @sendChat to, msg

    return null

  # Public: extended Adapter method to reply to a message
  #
  # envelope - A Object with message, room and user details.
  # messages  - One or more strings to send.
  #
  # Returns nothing
  reply: (envelop, messages...) ->
    reply_messages = []

    for msg in messages
      reply_messages.push "@#{envelop.user.name}, #{msg}"

    @send envelop, reply_messages...
    return null

  # Public: extended Adapter method to emote a message
  #
  # envelope - A Object with message, room and user details.
  # messages  - One or more strings to send.
  #
  # Returns nothing
  emote: (envelop, messages...) ->
    to = if envelop.room then envelop.room else envelop.user.id

    @robot.logger.debug "In emote with string:#{JSON.stringify messages}"
    for msg in messages
      @sendEmote to, msg

    return null

  # Private: generic sendChat helper to send\reply to a message
  #
  # to - the jid to send the message to
  # text - the string to send to the jid
  #
  # Return nothing
  sendChat: (to, text) ->
    item = {
      id: @getClient().nextId()
      to: to
      text: text
    }
    @getClient().sendChat item
    return null

  # Private: helper for sending a chat as an emote
  #
  # to - the jid to send the message to
  # text - the string to send to the jid
  #
  # Return nothing
  sendEmote: (to, text) ->
    item = {
      id: @getClient().nextId()
      to: to
      text: "/me #{text}"
      extras: {
        type: "emote"
        emote: {
          text: text
        }
      }
    }
    @getClient().sendChat item
    return null

  # Public: extended Adapter method for cleanup on close
  #
  # Returns nothing
  close: ->
    @disconnect()
    process.exit()


exports.use = (robot) ->
  new RyverBot robot
