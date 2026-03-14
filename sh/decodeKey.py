import json, base64
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateNumbers, rsa_crt_iqmp, rsa_crt_dmp1, rsa_crt_dmq1
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers
from cryptography.hazmat.backends import default_backend

def b64d(s):
    s += '=' * (-len(s) % 4)
    return int.from_bytes(base64.urlsafe_b64decode(s), 'big')

jwk = json.load(open('account_jwk.json'))
nums = RSAPrivateNumbers(b64d(jwk['p']), b64d(jwk['q']), b64d(jwk['d']),
       rsa_crt_dmp1(b64d(jwk['d']), b64d(jwk['p'])),
       rsa_crt_dmq1(b64d(jwk['d']), b64d(jwk['q'])),
       rsa_crt_iqmp(b64d(jwk['p']), b64d(jwk['q'])),
       RSAPublicNumbers(b64d(jwk['e']), b64d(jwk['n'])))
key = nums.private_key(default_backend())
print(key.private_bytes(Encoding.PEM, PrivateFormat.TraditionalOpenSSL, NoEncryption()).decode())