<?php
  parse_str(getenv('QUERY_STRING') ?: '', $_GET);

  function toS($_array){
    if(!is_array($_array) || count($_array) == 0) return '[]';
    $size = count($_array);
    $ret = '[';
    foreach($_array as $i => $a){ 
      $ret .= '"'. $i . '":"' . $a .'"';
      if($size > 1){ $ret .= ', '; $size--; }
    }
    return($ret . ']');
  }

  function readConfig(){
    $scriptfile = getenv('SCRIPT_FILENAME') ?: '';
    if($scriptfile == '') return [];
    $configloc = substr($scriptfile, 0, strrpos($scriptfile, '/')) . '/web.config';
    if(file_exists($configloc)){
      $config = [];
      $configcont = explode("\n", file_get_contents($configloc));
      foreach($configcont as $line){
        if(substr($line, 0, 1) != '#' && chop($line) != ''){
          $marray = explode('=', $line);
          $config[chop($marray[0])] = strrev(chop(strrev(chop($marray[1]))));
        }
      }
      return $config;
    }
    return [];
  }

  function move_upload_file($tmp, $to){
    if($tmp != '') return copy($tmp, $to);
  }

  $_REQUEST = $_GET;
  $_COOKIE = Array();
  $_FILES = Array();

  $_CONFIG = readConfig();
  $f = fopen( 'php://stdin', 'r' );
  stream_set_blocking($f, 0);

  while(false !== ($line = fgets($f))){
    $marray = explode('=', $line);
    if(isset($marray[0]) && isset($marray[1]) && isset($marray[2])){
      if($marray[0] == "S"){
        $_SERVER[urldecode($marray[1])] = urldecode(chop(join("=", array_slice($marray, 2))));
      }else if($marray[0] == "C"){
        $_COOKIE[urldecode($marray[1])] = urldecode(chop(join("=", array_slice($marray, 2))));
      }else if($marray[0] == "F"){
        $_FILES[urldecode($marray[1])]["name"][urldecode(chop($marray[2]))] = urldecode(chop($marray[2]));
        $_FILES[urldecode($marray[1])]["mime"][urldecode(chop($marray[2]))] = urldecode(chop($marray[3]));
        $_FILES[urldecode($marray[1])]['error'][urldecode(chop($marray[2]))] = 0;
        $_FILES[urldecode($marray[1])]["tmp_name"][urldecode(chop($marray[2]))] = urldecode(chop($marray[4]));
      }else{
        $_POST[urldecode($marray[1])] = urldecode(chop(join("=", array_slice($marray, 2))));
      }
    }
  }
  fclose($f);

  $api_loaded = true;
  return 1;
?>
