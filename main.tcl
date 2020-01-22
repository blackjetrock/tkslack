#!/usr/bin/env wish

package require Tk
package require websocket
package require http
package require tls
package require json

# Create interpreter for channel code
interp create -safe safeint

# app
wm title . "Slack"
wm geometry . 1000x700

# components
set font {Courier 15 normal}

frame .lfrm
entry .lfrm.chat -textvariable chat_message -font $font -highlightthickness 0 -borderwidth 2 -foreground #222222 -background #dddddd -relief flat
text .lfrm.log -yscrollcommand {.lfrm.log_scroll set} -highlightthickness 0 -font $font -undo 1  -foreground #222222 -selectbackground #bcbcbc -selectforeground #000000 -border 10 -relief flat
scrollbar .lfrm.log_scroll -command {.log yview}

frame .rfrm
entry .rfrm.filter -textvariable current -font $font -highlightthickness 0 -borderwidth 1 -foreground #222222 -background #dddddd -relief flat -justify left
listbox .rfrm.channels -listvariable select_channels -borderwidth 0 -font $font -yscrollcommand {.rfrm.channels_scroll set} -highlightcolor #ffffff -selectborderwidth 0 -selectforeground #222222 -selectbackground #dddddd -selectmode single
scrollbar .rfrm.channels_scroll -command {.rfrm.channels yview}

# layout
pack .lfrm -side left -fill both -expand y
pack .lfrm.log_scroll -side right -fill y
pack .lfrm.chat -side bottom -fill both
pack .lfrm.log -side left -fill both -expand y -anchor n

pack .rfrm -side right -fill y
pack .rfrm.channels_scroll -side right -fill y
pack .rfrm.filter -side top -fill x
pack .rfrm.channels -side right -fill both -expand y

# menu
menu .menu
menu .menu.apple -tearoff 0
.menu.apple add command -label "About" -command {
  tk_messageBox -title "About tkslack" -message "tkslack v1.0.0" -detail "By Nick Barth 2019"
}
.menu add cascade -menu .menu.apple
. configure -menu .menu

# enable https
http::register https 443 [list ::tls::socket -tls1 1]
# websocket::loglevel debug

# globals
set token_file "~/.tkslack"
set token ""
set sock {}

set id ""
set current "slackbot"
set current_id ""
set chat_message ""

set select_channels []

set messages []
set members []
set channels []

array set members_by_hash {}
array set channels_by_name {}

# procs
proc request { url {data ""} } {
  global token

  set request [http::geturl "${url}&token=${token}" -query $data]
  set body [http::data $request]
  return [json::json2dict $body]
}

proc handler { sock type data } {
  global current_id

  switch -- $type {
    "connect" { puts "Connected on $sock" }
      "text" {
	  # puts $data
	  set json [json::json2dict $data]
	  dict with json {
	      if {$type == "message" && $channel == $current_id} {
		  add_message_check $ts $user $text end
		  .lfrm.log see end
	      }
	  }
      }
  }
}

proc save_token {} {
  global token token_file
  set fp [open $token_file w]
  puts $fp $token
  close $fp
}

proc enter_token {} {
  global font token_file token
  set done 0

  toplevel .twin
  wm title .twin "Set Token"
  wm resizable .twin 0 0
  wm transient .twin .

  frame .twin.frm
  label .twin.frm.lbl -text "Enter your token: " -justify left
  entry .twin.frm.txt -textvariable token -font $font -highlightthickness 0 -borderwidth 2 -foreground #222222 -background #dddddd -relief flat

  button .twin.frm.okbtn -text "Save" -command { save_token; set done 1 } -padx 10
  button .twin.frm.cancelbtn -text "Cancel" -command { set token ""; set done 1 } -padx 10

  pack .twin.frm -fill both -padx 10 -pady 10
  pack .twin.frm.lbl -side top -anchor nw
  pack .twin.frm.txt -fill x -pady 10

  pack .twin.frm.okbtn -side right
  pack .twin.frm.cancelbtn -side right

  focus .twin.frm.txt

  bind .twin.frm.txt <Return> { save_token; set done 1 }
  bind .twin.frm.txt <Escape> { set token ""; set done 1 }

  vwait done
  destroy .twin
  return [expr {$token != ""}]
}

proc set_token {} {
  global token_file token env

  if { $token != "" } {
    return true
  }

  if { [info exists env(TKSLACK_TOKEN) ] } {
    set token $env(TKSLACK_TOKEN)
    return true
  }

  if { [file exists $token_file] } {
    set fp [open $token_file r]
    set token [string trim [read $fp]]
    close $fp
    return true
  }

  if { [enter_token] } {
    return true
  }

  return false
}

proc connect {} {
  global id sock token_file
  if {[catch {
    set data [request "https://slack.com/api/rtm.start?"]
    set ws_url [dict get $data url]
    set sock [websocket::open $ws_url handler]
    set id [dict get [dict get $data self] id]
  }]} {
    file delete $token_file
    tk_messageBox -title "Invalid Token Error" -message "You require a valid file." -detail "Please get one from: https://api.slack.com/custom-integrations/legacy-tokens" -icon error
    exit
  }
}

proc socket_send { sock type channel text } {
  websocket::send $sock text [subst {{
    "type":    "${type}",
    "channel": "${channel}",
    "text":    "${text}"
  }}]
}

proc post_message { channel message } {
  set query [http::formatQuery channel $channel text $message as_user true]
  return [request "https://slack.com/api/chat.postMessage?" $query]
}

proc get_messages { channel } {
  set data [request "https://slack.com/api/conversations.history?channel=${channel}"]

  if {[dict get $data ok] == false} {
    tk_messageBox -title "Error" -message "Channel not found." -icon error
    return []
  }

  return [dict get $data messages]
}
proc automsg {msg} {
    global current_id
    
     post_message $current_id $msg
}

proc add_message {ts user_id msg pos} {
  global members_by_hash
    global current_id
    
  set user $members_by_hash($user_id)
  set date [clock format [expr int($ts)] -format %T]
    .lfrm.log insert $pos "\[$date\] <$user> $msg\n"
}

set ::RESPONSES {
    {critchle " pies " "...and gravy..."}
    {dfount   " Z80 " "(processor of the gods)"}
    {amenadue "hello me" "Hello you"}

}

proc add_message_check {ts user_id msg pos} {
  global members_by_hash
    global current_id
    puts "add message check"
  set user $members_by_hash($user_id)
  set date [clock format [expr int($ts)] -format %T]
    .lfrm.log insert $pos "\[$date\] <$user> $msg\n"

    if { [regexp -- "evaluate:(.*)" [string tolower $msg] all expr] } {
        set answer "I'm sorry, $user, I can't work that out."
        catch {
            set answer [interp eval safeint expr $expr]
        }
        after 1000 "automsg \"$answer\""
    }

    if { [regexp -- "your review comments" [string tolower $msg]] } {
        set fn "/organic_ses/review_comments/$user\.comments"
        set txt "No comment"
        catch {
        set f [open $fn]
        set txt [read $f]
        close $f
        }
        after 1000 "automsg \"$txt\""
    }
    
    foreach response $::RESPONSES {
        set resp_user    [lindex $response 0]
        set resp_pattern [lindex $response 1]
        set resp_resp    [lindex $response 2]
        puts "$resp_user $resp_pattern $resp_resp"
        if { [string compare $user $resp_user] == 0 } {
            if { [regexp -- $resp_pattern $msg] } {
                after 1000 "automsg \"$resp_resp\""
            }
        }
    }
}

proc draw_messages { channel } {
  global messages

  .lfrm.log delete 1.0 end

  foreach message $messages {
    dict with message {
      if {$type == "message"} {
        add_message $ts $user $text 1.0
      }
    }
  }

  .lfrm.log see end
}

proc pull_messages { channel } {
  global messages current

  set messages [get_messages $channel]
  draw_messages $channel
}

proc old_get_channels {} {
    set data [request "https://slack.com/api/conversations.list?types=im,public_channel&exclude_archived=true"]
    puts $data
  return [dict get $data channels]
}

proc get_channels {} {

    set cursor "-"
    set done 0
    set pagei 0

    while { !$done } {
        if { $cursor == "-" } {
            set data [request "https://slack.com/api/conversations.list?types=mpim,im,private_channel,public_channel&exclude_archived=false&limit=1000"]
        } else {
            set data [request "https://slack.com/api/conversations.list?types=mpim,im,private_channel,public_channel&exclude_archived=false&limit=1000&cursor=$cursor"]
        }
        
        set f [open data w]
        puts $f $data
        close $f

        set ch [dict get $data channels]
        foreach c $ch {
            lappend channels $c
        }
        
        set metadata [dict get $data response_metadata]
        set next_cursor [dict get $metadata next_cursor]
        set cursor $next_cursor

        if { $cursor == "" } {
            set done 1
        }

        incr pagei
        puts "Fetching page $pagei"
    }

    set f [open channeldata w]
    puts $f $channels
    close $f
    return $channels
}

proc get_members {} {
  set data [request "https://slack.com/api/users.list?"]
  return [dict get $data members]
}

proc lmap {_var list body} {
    upvar 1 $_var var
    set res {}
    foreach var $list {lappend res [uplevel 1 $body]}
    set res
}

proc draw_channels {} {
  global channels_by_name select_channels
  set select_channels [lsort [lmap n [array names channels_by_name] {expr $n}]]
}

proc pull_channels {} {
  global channels members select_channels members_by_hash channels_by_name

  set channels [get_channels]
  set members [get_members]

  # setup hashes for quick lookups
  foreach member $members {
    dict with member {
      set members_by_hash($id) $name
    }
  }

  # set channel name - id
    foreach channel $channels {
	puts "Channel:$channel"
        catch {
            dict with channel {
                if {$is_im} {
                    set channels_by_name("$members_by_hash($user)") $id
                } else {
                    set channels_by_name("#${name}") $id
                }
            }
        }
    }
    draw_channels
}

proc set_channel { name } {
  global current current_id channels_by_name select_channels

  if {! [info exists channels_by_name("${name}")]} {
    # reset current
    set index [.rfrm.channels curselection]
    set current [lindex $select_channels $index]

    tk_messageBox -title "Error" -message "Channel `${name}` not found." -icon error
    return
  }

  set id $channels_by_name("${name}")
  set current $name
  set current_id $id

  pull_messages $id

  # set selected channel
  .rfrm.channels selection clear 0 end
  .rfrm.channels selection set [lsearch $select_channels $name]
}

proc ping { sock } {
  global id

  websocket::send $sock text [subst {{
    "id":   "${id}",
    "type": "ping"
  }}]

  after 60000 ping $sock
}

proc initialize {} {
  global sock current token

  if { [set_token] } {
    connect
    pull_channels
    set_channel $current

    after 60000 ping $sock

    focus .lfrm.chat
  } else {
    tk_messageBox -title "Invalid Token Error" -message "You require a valid file." -detail "Please get one from: https://api.slack.com/custom-integrations/legacy-tokens" -icon error
    exit
  }
}

# keyboard bindings
bind .lfrm.chat <Return> {
  post_message $current_id $chat_message
  set chat_message ""
}

bind . <Command-k> {
  set current ""
  focus .rfrm.filter
}

bind . <Command-l> {
  set index [.rfrm.channels curselection]
  set current [lindex $select_channels $index]

  set chat_message ""
  focus .lfrm.chat
}

bind .rfrm.filter <Return> {
  if { $current != "" } {
    set_channel $current
  }

  focus .lfrm.chat
}

bind .rfrm.filter <Escape> {
  set index [.rfrm.channels curselection]
  set current [lindex $select_channels $index]
  focus .lfrm.chat
}

# bind .lfrm.log <KeyPress> { break }

bind .rfrm.channels <<ListboxSelect>> {
  set index [%W curselection]

  if { $index != "" } {
    set_channel [lindex $select_channels $index]
  }

  focus .lfrm.chat
}

initialize
