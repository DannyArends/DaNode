<?php
  include 'api/danode.php';
  
  echo "HTTP/1.1 200 OK\n";
  echo "Content-Type: text/html; charset=utf-8\n";
  echo "Server: " . $_SERVER["SERVER_SOFTWARE"] . "\n\n";
?>
<html>
  <head>
    <title>DaNode 'user defined' CGI (PHP) test script</title>
    <meta name='author' content='Danny Arends'>
  </head>
  <body>
    DaNode 'user defined' CGI (PHP) test script<br/>
    Config: <small><?php echo toS($_CONFIG); ?></small><br>
    Server: <small><?php echo toS($_SERVER); ?></small><br>
    <form action='php.php' method='post' enctype='multipart/form-data'>
    <table>
      <tr><td><a href='php.php?test=GET&do'>GET</a>:</td><td><?php echo toS($_GET); ?> </td></tr>
      <tr><td>POST: </td><td> <?php echo toS($_POST); ?> </td></tr>
      <tr><td>Test: </td><td> <input name='test' type='text'></td></tr>
      <tr><td>File: </td><td> <input name='file' type='file'></td></tr>
      <tr><td>&nbsp;</td><td> <input type='submit' value='POST'></td></tr>
    </table>
    </form>
  </body>
</html>

