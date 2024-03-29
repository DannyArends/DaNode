<?php
  include 'api/danode.php';

  header('Content-Type: text/html; charset=utf-8');
  header('Server: ' . $_SERVER["SERVER_SOFTWARE"]);
  setcookie("whowants", "a cgi-cookie");
  setcookie("anda", "empty");
  header('Status: 200 OK');
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
      <tr><td><a href='php.php?test=GET&do'>Get</a>:</td><td><?php echo toS($_GET); ?> </td></tr>
      <tr><td>Post: </td><td> <?php echo toS($_POST); ?> </td></tr>
      <tr><td>Files: </td><td> <?php echo var_dump($_FILES); ?> </td></tr>
      <tr><td>Cookie: </td><td> <?php echo toS($_COOKIE); ?> </td></tr>
      <tr><td>Test: </td><td> <input name='test' type='text'></td></tr>
      <tr><td>File: </td><td> <input name='file' type='file'></td></tr>
      <tr><td>&nbsp;</td><td> <input type='submit' value='POST'></td></tr>
    </table>
    </form>
<?
  if($_FILES["file"] != ''){
    $target_file = $_SERVER["DOCUMENT_ROOT"] . "/". $_FILES["file"]["name"];
    if (move_upload_file($_FILES["file"]["tmp_name"], $target_file)) {
      echo "The file ". $_FILES["file"]["name"]. " has been uploaded.";
    } else {
      echo "Error uploading to: " . $target_file;
    }
  }
?>
  </body>
</html>
