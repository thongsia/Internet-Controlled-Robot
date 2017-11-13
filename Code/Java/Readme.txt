This directory contains the java source files for the project. They are
archived in the .tar.gz (or .tgz) format.

The project was developed on the Linux platform. Hence they should be
used on a linux box. However, they should be equally adaptable onto any
Java platform.

Some important directories are:
	$JAVA_HOME = /usr/local/java
	$HTTP_HOME = /var/lib/httpd/

classes.tgz contains the utility classes. They are to be installed under
$JAVA_HOME/lib.

clients.tgz contains the java source files for the remote applet. They
goes under $HTTP_HOME/htdocs

server.tgz contains the source files for the robot control program. They
can be installed anywhere, really. To run the control program, make sure
ports 8000 and 8001 are free (they usually are), that the robot is
plugged in, and type the command "java Server".