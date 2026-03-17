/** danode/includes.d - include openssl
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
#define OPENSSL_NO_DEPRECATED
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>
#include <openssl/pem.h>
#include <openssl/evp.h>
