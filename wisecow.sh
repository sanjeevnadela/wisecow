#!/usr/bin/env bash

SRVPORT=4499
RSPFILE=response

rm -f $RSPFILE
mkfifo $RSPFILE

get_api() {
	read line
	echo $line
}

handleRequest() {
    # 1) Process the request
	get_api
	mod=$(fortune)
	body="<pre>$(cowsay "$mod")</pre>"
	content_length=$(echo -n "$body" | wc -c)
cat <<EOF > $RSPFILE
HTTP/1.1 200 OK
Content-Type: text/html; charset=UTF-8
Content-Length: $content_length
Connection: close

$body
EOF
}

prerequisites() {
	command -v cowsay >/dev/null 2>&1 &&
	command -v fortune >/dev/null 2>&1 || 
		{ 
			echo "Install prerequisites."
			exit 1
		}
}

main() {
	prerequisites
	echo "Wisdom served on port=$SRVPORT..."

       while true; do
	       # Listen for a connection, handle one request, then close
	       { nc -l 0.0.0.0 $SRVPORT < $RSPFILE; } &
	       handleRequest
	       wait $!
       done
}

main
