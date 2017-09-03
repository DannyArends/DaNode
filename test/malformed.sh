./test/empty.req localhost 80 www.dannyarends.nl / | telnet
./test/empty.req localhost 80 127.0.0.1 / | telnet
./test/empty.req localhost 80 www.xyz.nl/ /index?ii7%20_/../php | telnet
