#!/bin/bash

# GPL3
# Copyright: 2010
# Matthew Bauer <mjbauer95@gmail.com>

# requires:
#  coreutils
#   md5sum
#  curl
#  bash

# optional:
#  xdg-open

api_key='c6e4096833557af81efb8e81130ebe50' # am I not supposed to give this out?
shared_secret='99a59d8237342a7e'

rtm_api='http://api.rememberthemilk.com/services/rest/'

todo_cfg="$HOME/.todo/config"

usage(){
	echo 'Todo.txt <--> Remember the Milk'
	echo -e '\tRemember the Milk push and pull syncing'
	echo -e "\tRight now pull works better than syncing, but they both work"
	echo
	echo "Usage: $0 [push|pull]"
	echo
	echo 'Options:'
	echo -e '\t-d/--config [config file]'
	echo -e "\t\tPlace of your config file (defaults to $todo_cfg)"
	echo
	echo -e '\t-o/--overwrite'
	echo -e '\t\tOverwrite todo.txt file (defaults to adding to it)'
	echo
	echo -e '\t-h/--help'
	echo -e '\t\tThis help page'
	exit 1
}

get_sig(){
	# no brief option in md5sum ?
	echo -n $shared_secret$(echo "$args" | tr '&' '\n' | sort | tr -d '\n' | tr -d '=') | md5sum | cut -d' ' -f1
}

login_rtm(){
	perm="$1";

	# http://www.rememberthemilk.com/services/api/methods/rtm.auth.getFrob.rtm
	args="method=rtm.auth.getFrob&api_key=$api_key"
	api_sig=$(get_sig "$args")
	url="$rtm_api?$args&api_sig=$api_sig"

	frob=$(curl -s "$url" | sed -rn 's|^<rsp stat="ok"><frob>(.*)</frob></rsp>$|\1|p')

	# http://www.rememberthemilk.com/services/api/authentication.rtm
	args="perms=$perm&frob=$frob&api_key=$api_key"
	api_sig=$(get_sig "$args")
	url="http://www.rememberthemilk.com/services/auth/?$args&api_sig=$api_sig"

	if $(which xdg-open >/dev/null 2>&1)
	then
		echo "We are now opening this url with xdg-open."
		echo "$url"
		xdg-open "$url" &> /dev/null &
	else
		echo "You don't have xdg-open installed (or at least it wasn't detected)"
		echo "Please open the url manually."
		echo "$url"
	fi

	read -p "Press any key when you have authorized this application..."

	# http://www.rememberthemilk.com/services/api/methods/rtm.auth.getToken.rtm
	args="method=rtm.auth.getToken&frob=$frob&api_key=$api_key"
	api_sig=$(get_sig "$args")
	url="$rtm_api?$args&api_sig=$api_sig"

	#eval $(curl -s "$url" | sed -rn 's|^<rsp stat="ok"><auth><token>(.*)</token><perms>'$perm'</perms><user id="(.*)" username="(.*)" fullname="(.*)"/></auth></rsp>$|token=\1;id=\2;username=\3;fullname="\4"|p')
	token=$(curl -s "$url" | sed -rn 's|^<rsp stat="ok"><auth><token>(.*)</token><perms>'$perm'</perms><user id="(.*)" username="(.*)" fullname="(.*)"/></auth></rsp>$|\1|p')
}

check_does_exist_on_rtm(){
		token="$1"
		filter="$2"

		# http://www.rememberthemilk.com/services/api/methods/rtm.tasks.getList.rtm
		#filter=$(echo "name:$line" | sed 's/ /%20/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/%/%25/g;s/\&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/:/%3A/g')
		#echo "$filter"
		#args="method=rtm.tasks.getList&filter=$filter&auth_token=$token&api_key=$api_key"
		args="method=rtm.tasks.getList&auth_token=$token&api_key=$api_key"
		api_sig=$(get_sig "$args")
		url="$rtm_api?$args&api_sig=$api_sig"
		curl -s "$url" | sed 's|<taskseries|\n<taskseries|g' | grep '<taskseries' | sed 's|</list></tasks></rsp>||' |
		while read line
		do
			name="$(echo "$line" | sed -rn 's|^<taskseries id=".*" created=".*" modified=".*" name="(.*)" source=".*" url=".*" location_id=".*"><tags.*/><participants.*/><notes.*/><task id=".*" due=".*" has_due_time=".*" added=".*" completed=".*" deleted=".*" priority=".*" postponed=".*" estimate=".*"/></taskseries>$|\1|p')"
			if [[ "$name" == "$filter" ]]
			then
				echo 1
				break
			fi
		done
}

push(){
	login_rtm 'write' # gets token

	source "$todo_cfg"

	cat $TODO_FILE | while read line
	do
		if [ $(check_does_exist_on_rtm "$token" "$line") == 1 ] # does exist
		then
			echo "'$line' exists not adding"
			continue
		else
			# http://www.rememberthemilk.com/services/api/methods/rtm.timelines.create.rtm
			args="method=rtm.timelines.create&auth_token=$token&api_key=$api_key"
			api_sig=$(get_sig "$args")
			url="$rtm_api?$args&api_sig=$api_sig"
			timeline=$(curl -s "$url" | sed 's|^<rsp stat="ok"><timeline>\(.*\)</timeline></rsp>$|\1|p')

			# http://www.rememberthemilk.com/services/api/methods/rtm.tasks.add.rtm
			# optional: parse, list_id
			# if parse=1 then "SmartAdd" will be used; that has RTM interpret natural language

			echo "Adding '$line' to Remember the Milk"

			args="method=rtm.tasks.add&name=$line&timeline=$timeline&auth_token=$token&api_key=$api_key"
			api_sig=$(get_sig "$args")
			url="$rtm_api?$args&api_sig=$api_sig"

			curl -s "$url"
		fi
	done

	#cat $TODO_DONE | while read line
	#do
	#	# http://www.rememberthemilk.com/services/api/methods/rtm.timelines.create.rtm
	#	args="method=rtm.timelines.create&auth_token=$token&api_key=$api_key"
	#	api_sig=$(get_sig "$args")
	#	url="$rtm_api?$args&api_sig=$api_sig"
	#	timeline=$(curl -s "$url" | sed 's|^<rsp stat="ok"><timeline>\(.*\)</timeline></rsp>$|\1|p')

		# http://www.rememberthemilk.com/services/api/methods/rtm.tasks.getList.rtm
	#	args="method=rtm.tasks.getList&filter=name%3A$line&auth_token=$token&api_key=$api_key"
	#	api_sig=$(get_sig "$args")
	#	url="$rtm_api?$args&api_sig=$api_sig"

	#	curl -s "$url"

		# http://www.rememberthemilk.com/services/api/methods/rtm.tasks.add.rtm
		# optional: parse, list_id
		# if parse=1 then "SmartAdd" will be used; that has RTM interpret natural language

	#	echo "Adding $line"

	#	args="method=rtm.tasks.add&name=$line&timeline=$timeline&auth_token=$token&api_key=$api_key"
	#	api_sig=$(get_sig "$args")
	#	url="$rtm_api?$args&api_sig=$api_sig"

	#	exit 1

	#	curl -s "$url"
	#done	
}

pull(){
	login_rtm 'read' # gets token

	source "$todo_cfg"

	if [ ! -z $overwrite_txt ]
	then
		echo "" | tee "$TODO_FILE" > /dev/null
	fi

	# http://www.rememberthemilk.com/services/api/methods/rtm.tasks.getList.rtm
	args="method=rtm.tasks.getList&auth_token=$token&api_key=$api_key"
	api_sig=$(get_sig "$args")
	url="$rtm_api?$args&api_sig=$api_sig"

	curl -s "$url" | sed 's|<taskseries|\n<taskseries|g' | grep '<taskseries' | sed 's|</list></tasks></rsp>||' |
	while read line
	do
		# load some xml variables
		eval $(echo "$line" | sed -rn 's|^<taskseries id=".*" created=".*" modified=".*" name="(.*)" source=".*" url=".*" location_id=".*"><tags.*/><participants.*/><notes.*/><task id=".*" due="(.*)" has_due_time="(.*)" added="(.*)" completed="(.*)" deleted="(.*)" priority="(.*)" postponed="(.*)" estimate="(.*)"/></taskseries>$|name="\1";due="\2";has_due_time="\3";added="\4";completed="\5";deleted="\6";priority="\7";postponed="\8";estimate="\9"|p')

		if [ -z "$completed" ]
		then
			if ! grep -q "$name" $TODO_FILE # it is not on the todo file
			then
				echo "Adding $name to $TODO_FILE"
				echo "$name" | tee -a "$TODO_FILE" > /dev/null
				# $TODO_SH add "$name"
			fi
		else
			if ! grep -q "$name" $DONE_FILE # it is not on the done file
			then
				echo "Adding $name to $DONE_FILE"
				echo "$name" | tee -a "$DONE_FILE" > /dev/null # it might be safer to use the interface
				# $TODO_SH add "$name"
			fi
		fi
	done
}

if [ -z "$@" ]
then
	usage
	exit
fi


while true; do
	case "$1" in
		-d|--config) shift; todo_cfg="$1";;
		-o|--overwrite) overwrite_txt=1;;
		push) push;;
		pull) pull;;
		'') exit;;
		--help) usage;;
		*) usage;;
	esac
	shift
done
