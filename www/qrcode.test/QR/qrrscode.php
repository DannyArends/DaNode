<?php
/**
 * PHP QR Code encoder - Reed&Solomon error correction support
 */

class QRrsItem {
  public $mm;                  // Bits per symbol 
  public $nn;                  // Symbols per block (= (1<<mm)-1) 
  public $alpha_to = array();  // log lookup table 
  public $index_of = array();  // Antilog lookup table 
  public $genpoly = array();   // Generator polynomial 
  public $nroots;              // Number of generator roots = number of parity symbols 
  public $fcr;                 // First consecutive root, index form 
  public $prim;                // Primitive element, index form 
  public $iprim;               // prim-th root of 1, index form 
  public $pad;                 // Padding bytes in shortened block 
  public $gfpoly;

  //----------------------------------------------------------------------
  public function modnn($x){
    while ($x >= $this->nn) {
      $x -= $this->nn;
      $x = ($x >> $this->mm) + ($x & $this->nn);
    }
    return $x;
  }

  //----------------------------------------------------------------------
  public static function init_rs_char($symsize, $gfpoly, $fcr, $prim, $nroots, $pad){
    // Common code for intializing a Reed-Solomon control block (char or int symbols)
    // Copyright 2004 Phil Karn, KA9Q
    // May be used under the terms of the GNU Lesser General Public License (LGPL)
    $rs = null;
    if($symsize < 0 || $symsize > 8)                     return $rs;            // Check parameter ranges
    if($fcr < 0 || $fcr >= (1<<$symsize))                return $rs;            // Check parameter ranges
    if($prim <= 0 || $prim >= (1<<$symsize))             return $rs;            // Check parameter ranges
    if($nroots < 0 || $nroots >= (1<<$symsize))          return $rs; // Can't have more roots than symbol values!
    if($pad < 0 || $pad >= ((1<<$symsize) -1 - $nroots)) return $rs; // Too much padding

    $rs = new QRrsItem();
    $rs->mm = $symsize;
    $rs->nn = (1<<$symsize)-1;
    $rs->pad = $pad;

    $rs->alpha_to = array_fill(0, $rs->nn+1, 0);
    $rs->index_of = array_fill(0, $rs->nn+1, 0);

    $NN =& $rs->nn;            // PHP style macro replacement ;)
    $A0 =& $NN;

    // Generate Galois field lookup tables
    $rs->index_of[0] = $A0; // log(zero) = -inf
    $rs->alpha_to[$A0] = 0; // alpha**-inf = 0
    $sr = 1;
  
    for($i=0; $i<$rs->nn; $i++) {
      $rs->index_of[$sr] = $i;
      $rs->alpha_to[$i] = $sr;
      $sr <<= 1;
      if($sr & (1<<$symsize)) { $sr ^= $gfpoly; }
      $sr &= $rs->nn;
    }

    if($sr != 1) return NULL;

    /* Form RS code generator polynomial from its roots */
    $rs->genpoly = array_fill(0, $nroots+1, 0);
    $rs->fcr = $fcr;
    $rs->prim = $prim;
    $rs->nroots = $nroots;
    $rs->gfpoly = $gfpoly;

    /* Find prim-th root of 1, used in decoding */
    for($iprim=1;($iprim % $prim) != 0;$iprim += $rs->nn){ ; /* intentional empty-body loop! */ }

    $rs->iprim = (int)($iprim / $prim);
    $rs->genpoly[0] = 1;

    for ($i = 0,$root=$fcr*$prim; $i < $nroots; $i++, $root += $prim) {
      $rs->genpoly[$i+1] = 1;
      // Multiply rs->genpoly[] by  @**(root + x)
      for ($j = $i; $j > 0; $j--) {
        if ($rs->genpoly[$j] != 0) {
          $rs->genpoly[$j] = $rs->genpoly[$j-1] ^ $rs->alpha_to[$rs->modnn($rs->index_of[$rs->genpoly[$j]] + $root)];
        } else {
          $rs->genpoly[$j] = $rs->genpoly[$j-1];
        }
      }
      // rs->genpoly[0] can never be zero
      $rs->genpoly[0] = $rs->alpha_to[$rs->modnn($rs->index_of[$rs->genpoly[0]] + $root)];
    }
    
    // convert rs->genpoly[] to index form for quicker encoding
    for ($i = 0; $i <= $nroots; $i++){ $rs->genpoly[$i] = $rs->index_of[$rs->genpoly[$i]]; }
    return $rs;
  }

  //----------------------------------------------------------------------
  public function encode_rs_char($data, &$parity){
    $MM       =& $this->mm;
    $NN       =& $this->nn;
    $ALPHA_TO =& $this->alpha_to;
    $INDEX_OF =& $this->index_of;
    $GENPOLY  =& $this->genpoly;
    $NROOTS   =& $this->nroots;
    $FCR      =& $this->fcr;
    $PRIM     =& $this->prim;
    $IPRIM    =& $this->iprim;
    $PAD      =& $this->pad;
    $A0       =& $NN;

    $parity = array_fill(0, $NROOTS, 0);

    for($i=0; $i< ($NN-$NROOTS-$PAD); $i++) {
      $feedback = $INDEX_OF[$data[$i] ^ $parity[0]];
      if($feedback != $A0) {
        $feedback = $this->modnn($NN - $GENPOLY[$NROOTS] + $feedback);
        for($j=1;$j<$NROOTS;$j++) {
          $parity[$j] ^= $ALPHA_TO[$this->modnn($feedback + $GENPOLY[$NROOTS-$j])];
        }
      }
      array_shift($parity);                // Shift 
      if($feedback != $A0) {
        array_push($parity, $ALPHA_TO[$this->modnn($feedback + $GENPOLY[0])]);
      } else {
        array_push($parity, 0);
      }
    }
  }

};

//##########################################################################
class QRrs {
  public static $items = array();

  //----------------------------------------------------------------------
  public static function init_rs($symsize, $gfpoly, $fcr, $prim, $nroots, $pad){
    foreach(self::$items as $rs) {
      if($rs->pad != $pad)       continue;
      if($rs->nroots != $nroots) continue;
      if($rs->mm != $symsize)    continue;
      if($rs->gfpoly != $gfpoly) continue;
      if($rs->fcr != $fcr)       continue;
      if($rs->prim != $prim)     continue;
      return $rs;
    }
    $rs = QRrsItem::init_rs_char($symsize, $gfpoly, $fcr, $prim, $nroots, $pad);
    array_unshift(self::$items, $rs);
    return $rs;
  }

};

