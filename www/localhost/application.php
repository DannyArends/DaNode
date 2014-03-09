<?php
  include 'api/danode.php';
  
  echo "HTTP/1.1 200 OK\n";
  echo "Content-Type: text/html; charset=utf-8\n";
  echo "Server: " . $_SERVER["SERVER_SOFTWARE"] . "\n\n";
  if($_GET['page'] == 'Index'){
?>
<h2>Cryptoexchange</h2>
This site provides the following services:
<ul>
 <li>Trade Cryptocurrencies</li>
 <li>Coin transfers</li>
</ul>
<?php
  }else if($_GET['page'] == 'Register'){
?>
<h2>Register</h2>
<table width='70%'>
  <tr>
    <td><span class="glyphicon glyphicon-list"></span> First name</td><td><input type='text' value='First name'></input></td>
    <td><span class="glyphicon glyphicon-list"></span> Last name</td><td><input type='text' value='Last name'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-user"></span> Username</td><td><input type='text' value='Username'></input></td>
    <td><span class="glyphicon glyphicon-envelope"></span> Email</td><td><input type='text' value='Email'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input type='password' value=''></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Confirm password</td><td><input type='password' value=''></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-question-sign"></span> Security question</td><td><input type='text' value='Security question?'></input></td>
    <td><span class="glyphicon glyphicon-ok"></span> Answer</td><td><input type='text' value='Answer'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-eye-open"></span> Captcha code</td><td colspan='3'><input type='text'></td>
  </tr>
  <tr><td colspan='4'><input type='submit' value='Register new account'></input></td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Login'){
?>
<h2>Login</h2>
<table  width='70%'>
  <tr>
    <td><span class="glyphicon glyphicon-user"></span> Username</td><td><input type='text' value='Username'></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input type='password' value=''></input></td>
  </tr>
  <tr><td colspan='4'>Forgot your password? Click <a href='#'>here</a></td></tr>
  <tr><td colspan='4'><input type='submit' value='Login'></input></td></tr>
</table>
<?php
  }
?>
