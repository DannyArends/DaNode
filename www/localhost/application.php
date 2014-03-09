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
If you do not have an account yet, please register for an account <a href='#'>here</a>. If you already have an account, you can log in <a href='#'>here</a>
<?php
  }else if($_GET['page'] == 'Register'){
?>
<h2>Register</h2>
<table width='70%'>
  <tr>
    <td><span class="glyphicon glyphicon-list"></span> First name</td><td><input id='firstname' name='firstname' type='text' value='First name'></input></td>
    <td><span class="glyphicon glyphicon-list"></span> Last name</td><td><input id='lastname' name='lastname' type='text' value='Last name'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-user"></span> Username</td><td><input id='username' name='username' type='text' value='Username'></input></td>
    <td><span class="glyphicon glyphicon-envelope"></span> Email</td><td><input id='email' name='email' type='text' value='Email'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input id='password' name='password' type='password' value=''></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Confirm password</td><td><input id='passconf' name='passconf' type='password' value=''></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-question-sign"></span> Security question</td><td><input id='squestion' name='squestion' type='text' value='Security question?'></input></td>
    <td><span class="glyphicon glyphicon-ok"></span> Answer</td><td><input id='sanswer' name='sanswer' type='text' value='Answer'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-eye-open"></span> Captcha code</td><td colspan='3'><input id='captcha' name='captcha' type='text'></td>
  </tr>
  <tr><td colspan='4'><input type='submit' value='Register New Account'></input></td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Login'){
?>
<h2>Login</h2>
<table width='70%'>
  <tr>
    <td><span class="glyphicon glyphicon-user"></span> Username</td><td><input id='username' name='username' type='text' value='Username'></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input id='password' name='password' type='password' value=''></input></td>
  </tr>
  <tr><td colspan='4'>Forgot your password? Click <a href='#'>here</a></td></tr>
  <tr><td colspan='4'><input type='submit' value='Login'></input></td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Overview'){
?>
<h2>Overview</h2>
<table width='40%'>
  <tr><td colspan='3'><h3>Balances</h3></td></tr>
  <tr><td>BTC:</td><td>0</td><td>0</td></tr>
  <tr><td>LTC:</td><td>0</td><td>0</td></tr>
  <tr><td>DOGE:</td><td>0</td><td>0</td></tr>
  <tr><td>TIPS:</td><td>0</td><td>0</td></tr>
  <tr><td colspan='2'><h3>Statistics</h3></td></tr>
  <tr><td>Total trades:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Open orders:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Deposits:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Withdrawls:</td><td>0</td><td>&nbsp;</td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Trade'){
?>
<h2>Trade coins</h2>

<?php
  }else if($_GET['page'] == 'Settings'){
?>
<h2>Account settings</h2>
<table width='70%'>
  <tr>
    <td><span class="glyphicon glyphicon-list"></span> First name</td><td><input id='firstname' name='firstname' type='text' value='First name'></input></td>
    <td><span class="glyphicon glyphicon-list"></span> Last name</td><td><input id='lastname' name='lastname' type='text' value='Last name'></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-envelope"></span> Email</td><td><input id='email' name='email' type='text' value='Email'></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input id='password' name='password' type='password' value=''></input></td>
  </tr>
  <tr><td colspan='4'><input type='submit' value='Update Account'></input></td></tr>
</table>

<?php
  }
?>

