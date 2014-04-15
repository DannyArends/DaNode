<?php
  include './api/danode.php';
  include "QR/qrlib.php";

//  echo "HTTP/1.1 200 OK\n";
//  echo "Content-Type: text/html; charset=utf-8\n";
//  echo "Server: " . $_SERVER["SERVER_SOFTWARE"] . "\n\n";

  $backColor = 0xFFFF00;
  $foreColor = 0xFF00FF;

  $link = "http://www.dannyarends.nl/" . $_GET["link"];
  QRcode::png($link, "www/localhost/QR/gen/test.png", "L", 4, 4, true, $backColor, $foreColor);
?>
<html>
  <body>
  <?php echo $link; ?><br/>
  <img src='/QR/gen/test.png'></img>
  </body>
</html>
