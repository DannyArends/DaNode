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
    <td><span class="glyphicon glyphicon-repeat"></span> Confirm password</td><td><input id='passconf' name='passconf' type='password' value=''></input></td>
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
    <td><span class="glyphicon glyphicon-user"></span> Username</td><td><input id='username' name='username' type='text' value=''></input></td>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input id='password' name='password' type='password' value=''></input></td>
  </tr>
  <tr><td colspan='4'>Forgot your password? Click <a href='#'>here</a></td></tr>
  <tr><td colspan='4'><input type='submit' value='Login'></input></td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Contact'){
?>
<h2>Contact us</h2>


<?php
  }else if($_GET['page'] == 'Overview'){
?>
<h2>Overview</h2>
<table width='70%'>
  <tr><td colspan='4'><h3>Balances</h3></td></tr>
  <tr><td>BTC: </td><td>0.00000000</td><td>0.00000000</td><td>
    <button id='BTC' onClick='cryptoengine.deposit(this.id);'  class='sbutton'><span class="glyphicon glyphicon-arrow-down"></span> Deposit</button>
    <button id='BTC' onClick='cryptoengine.withdraw(this.id);' class='sbutton'><span class="glyphicon glyphicon-arrow-up"></span> Withdraw</button>
  </td></tr>
  <tr><td>LTC: </td><td>0.00000000</td><td>0.00000000</td><td>
    <button id='LTC' onClick='cryptoengine.deposit(this.id);'  class='sbutton'><span class="glyphicon glyphicon-arrow-down"></span> Deposit</button>
    <button id='LTC' onClick='cryptoengine.withdraw(this.id);' class='sbutton'><span class="glyphicon glyphicon-arrow-up"></span> Withdraw</button>
  </td></tr>
  <tr><td>DOGE:</td><td>0.00000000</td><td>0.00000000</td><td>
    <button id='DOGE' onClick='cryptoengine.deposit(this.id);'  class='sbutton'><span class="glyphicon glyphicon-arrow-down"></span> Deposit</button>
    <button id='DOGE' onClick='cryptoengine.withdraw(this.id);' class='sbutton'><span class="glyphicon glyphicon-arrow-up"></span> Withdraw</button>
  </td></tr>
  <tr><td>TIPS:</td><td>0.00000000</td><td>0.00000000</td><td>
    <button id='TIPS' onClick='cryptoengine.deposit(this.id);'  class='sbutton'><span class="glyphicon glyphicon-arrow-down"></span> Deposit</button>
    <button id='TIPS' onClick='cryptoengine.withdraw(this.id);' class='sbutton'><span class="glyphicon glyphicon-arrow-up"></span> Withdraw</button>
  </td></tr>
  <tr><td colspan='4'><h3>Statistics</h3></td></tr>
  <tr><td>Total trades:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Open orders:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Deposits:</td><td>0</td><td>&nbsp;</td></tr>
  <tr><td>Withdrawls:</td><td>0</td><td>&nbsp;</td></tr>
</table>
<?php
  }else if($_GET['page'] == 'Trade'){
?>
<h2>Trade coins</h2>
<button id='BTC_LTC' onClick='cryptoengine.setMarket(this.id);'  class='mbutton'>BTC <span class="glyphicon glyphicon-resize-horizontal"></span> LTC</button>
<button id='DOGE_BTC' onClick='cryptoengine.setMarket(this.id);'  class='mbutton'>DOGE <span class="glyphicon glyphicon-resize-horizontal"></span> BTC</button>
<button id='DOGE_LTC' onClick='cryptoengine.setMarket(this.id);'  class='mbutton'>DOGE <span class="glyphicon glyphicon-resize-horizontal"></span> LTC</button>
<button id='TIPS_LTC' onClick='cryptoengine.setMarket(this.id);'  class='mbutton'>TIPS <span class="glyphicon glyphicon-resize-horizontal"></span> LTC</button>
<h3>Graph</h3>
Graph
<h3>Buy / Sell</h3>
<table width='70%'>
  <tr><td class='darkerbg' colspan='2'><h4 class='cntr'>Buy</h4></td><td>&nbsp;</td><td class='darkerbg' colspan='2'><h4 class='cntr'>Sell</h4></td></tr>
  <tr>
    <td>Buy:</td><td><input type='text' value='0.00000000' class='limw'></input><br><input type='text' value='0.00000000' class='limw'></input></td>
      <td class='darkerbg'>&nbsp;</td>
    <td>Sell:</td><td><input type='text' value='0.0000000' class='limw'></input><br><input type='text' value='0.00000000' class='limw'></input></td>
  </tr>
  <tr>
    <td>Total:</td><td>0.000000</td>
      <td class='darkerbg'>&nbsp;</td>
    <td>Total:</td><td>0.000000</td>
  </tr>
  <tr>
    <td>Fee:</td><td>0.000000</td>
      <td class='darkerbg'>&nbsp;</td>
    <td>Fee:</td><td>0.000000</td>
  </tr>
  <tr>
    <td>Net total:</td><td>0.000000</td>
      <td class='darkerbg'>&nbsp;</td>
    <td>Net total:</td><td>0.000000</td>
  </tr>

  <tr>
    <td>&nbsp;</td><td><button class='mbutton'><span class="glyphicon glyphicon-ok-sign"></span> BUY</button></td>
    <td class='darkerbg'>&nbsp</td>
    <td>&nbsp;</td><td><button class='mbutton'><span class="glyphicon glyphicon-ok-sign"></span> SELL</button></td>
  </tr>
</table>
<h3>Open orders</h3>
<ul>
<li>No orders found</li>
</ul>
<h3>Market depth</h3>
Summarized overview of open orders.
<table width='70%'>
  <tr><td colspan='2' class='darkerbg'><h4 class='cntr'>Buy</h4></td><td>&nbsp</td><td colspan='2' class='darkerbg'><h4 class='cntr'>Sell</h4></td></tr>
  <tr><td><h4 class='cntr'>Price</h4></td><td><h4 class='cntr'>Quantity</h4></td><td class='darkerbg'>&nbsp</td><td><h4 class='cntr'>Price</h4></td><td><h4 class='cntr'>Quantity</h4></td></tr>
</table>
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
    <td colspan='2'>&nbsp;</td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-pencil"></span> New password</td><td><input id='passnew' name='passnew' type='password' value=''></input></td>
    <td><span class="glyphicon glyphicon-repeat"></span> Confirm new password</td><td><input id='passconf' name='passconf' type='password' value=''></input></td>
  </tr>
  <tr>
    <td><span class="glyphicon glyphicon-pencil"></span> Password</td><td><input id='password' name='password' type='password' value=''></input></td>
    <td colspan='2'><input type='submit' value='Update Account'></input></td>
  </tr>
</table>

<?php
  }
?>

