<?php
  include './api/danode.php';
  include "QR/qrlib.php";

  echo "HTTP/1.1 200 OK\n";
  echo "Content-Type: image/png; charset=utf-8\n";
  echo "Server: " . $_SERVER["SERVER_SOFTWARE"] . "\n\n";

  $link = "http://www.dannyarends.nl/" . $_GET["link"];
  QRcode::png($link);
?>
