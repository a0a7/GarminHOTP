import Toybox.Time;
import Toybox.Test;
import Toybox.Lang;

import Hmac;
import Base32;

(:glance)
module Otp {
  const powers = [
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000,
    1000000000,
  ];

  class BaseOtp {
    private var digits;
    private var secret;
    private var algo as Number;

    function initialize(secretKey, digitCount, algorithm) {
      digits = digitCount;
      secret = secretKey;
      algo = algorithm;
    }

    function getSecret() {
      return secret;
    }

    function setDigitCount(num) {
      self.digits = num;
    }

    function getDigitCount() {
      return digits;
    }

    function getAlgorithm() {
      return algo;
    }

    function code() {
      return "";
    }
  }

  class Hotp extends BaseOtp {
    private var counter;
    private var counterKey as String?;

    // secretKey - secret value encoded with Base32
    // algorithm - 0 = SHA-1, 1 = SHA-256
    // digitCount - number of digits in the OTP code
    // counterKey - storage key for persisting counter (optional)
    function initialize(secretKey, algorithm, digitCount, counterKey) {
      BaseOtp.initialize(secretKey, digitCount, algorithm);
      self.counterKey = counterKey;
      if (counterKey != null) {
        counter = Application.Storage.getValue(counterKey);
        if (counter == null) {
          counter = 0;
        }
      } else {
        counter = 0;
      }
    }

    protected function intToBytes(v as Numeric) {
      var result = [0, 0, 0, 0, 0, 0, 0, 0];
      for (var i = 7; i >= 0; i--) {
        var b = v & 0xff;
        result[i] = b;
        v = v >> 8;
      }
      return result;
    }

    protected function generate() as String {
      var text = intToBytes(counter);
      counter += 1;
      // Save counter to storage if key is provided
      if (counterKey != null) {
        Application.Storage.setValue(counterKey, counter);
      }
      var hash =
        Hmac.hmacSha(getSecret(), getAlgorithm(), text) as Array<Number>;
      var offset = (hash[hash.size() - 1] & 0x0f).toNumber();
      var binary =
        ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);

      var otp = binary % powers[getDigitCount()];
      var format = "%0" + getDigitCount() + "d";
      return otp.format(format);
    }

    function code() as String {
      return generate();
    }

    function getCounter() {
      return counter;
    }

    function setCounter(newCounter) {
      self.counter = newCounter;
      // Save counter to storage if key is provided
      if (counterKey != null) {
        Application.Storage.setValue(counterKey, counter);
      }
    }

    function resetCounter() {
      counter = 0;
      if (counterKey != null) {
        Application.Storage.setValue(counterKey, counter);
      }
    }
  }

  class Totp extends Hotp {
    private var timeStep = 30;
    private var cachedCode as String?;
    private var cachedTime as Long;

    // secretKey - secret value encoded with Base32
    // algorithm - 0 = SHA-1, 1 = SHA-256
    // digitCount - number of digits in the OTP code
    // timeStep - time window for a TOTP code
    function initialize(secretKey, algorithm, digitCount, timeStep) {
      Hotp.initialize(secretKey, algorithm, digitCount, null);
      self.timeStep = timeStep;
      self.cachedCode = null;
      self.cachedTime = 0 as Long;
    }

    function codeForEpoch(epoch) as String {
      var time = (epoch / timeStep).toLong();
      if (time != cachedTime || cachedCode == null || "".equals(cachedCode)) {
        cachedTime = time;
        setCounter(time);
        cachedCode = generate();
      }
      return cachedCode;
    }

    function code() as String {
      var now = Time.now().value();
      return codeForEpoch(now);
    }

    function getTimeStep() {
      return timeStep;
    }

    function getPercentTimeLeft() as Float {
      var now = Time.now().value();
      return 1 - (now % timeStep).toFloat() / timeStep;
    }

    function getSecondsLeft() as Float {
      var now = Time.now().value();
      return timeStep - (now % timeStep);
    }
  }

  function TotpFromBase32(key as String) as Totp {
    var secret = Base32.base32decode(key);
    var totp = new Totp(secret, 0, 6, 30);
    return totp;
  }

  function TotpFromBase32Digits(key as String, digits as Numeric) as Totp {
    var secret = Base32.base32decode(key);
    var totp = new Totp(secret, 0, digits, 30);
    return totp;
  }

  function TotpFromBase32DigitsTimeStep(
    key as String,
    digits as Numeric,
    timeStep as Numeric
  ) as Totp {
    var secret = Base32.base32decode(key);
    var totp = new Totp(secret, 0, digits, timeStep);
    return totp;
  }

  function TotpFromBase32AlgoDigitsTimeStep(
    key as String,
    algo as Numeric,
    digits as Numeric,
    timeStep as Numeric
  ) as Totp {
    var secret = Base32.base32decode(key);
    var totp = new Totp(secret, algo, digits, timeStep);
    return totp;
  }

  function HotpFromBase32(key as String, counterKey as String) as Hotp {
    var secret = Base32.base32decode(key);
    var hotp = new Hotp(secret, 0, 6, counterKey);
    return hotp;
  }

  function HotpFromBase32Digits(key as String, digits as Numeric, counterKey as String) as Hotp {
    var secret = Base32.base32decode(key);
    var hotp = new Hotp(secret, 0, digits, counterKey);
    return hotp;
  }

  function HotpFromBase32AlgoDigits(
    key as String,
    algo as Numeric,
    digits as Numeric,
    counterKey as String
  ) as Hotp {
    var secret = Base32.base32decode(key);
    var hotp = new Hotp(secret, algo, digits, counterKey);
    return hotp;
  }

  (:test)
  function TestOtp(logger as Test.Logger) {
    var key = "12345678901234567890";
    var otp = new Totp(key.toUtf8Array(), 0, 8, 30);

    var expected = "94287082";
    var actual = otp.codeForEpoch(59);
    if (!expected.equals(actual)) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    }

    expected = "07081804";
    actual = otp.codeForEpoch(1111111109);
    if (!expected.equals(actual)) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    } else {
      return true;
    }
  }

  (:test)
  function TestOtpSha256(logger as Test.Logger) {
    var key = "12345678901234567890";
    var otp = new Totp(key.toUtf8Array(), 1, 8, 30);

    var expected = "32247374";
    var actual = otp.codeForEpoch(59);
    if (!expected.equals(actual)) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
    }

    expected = "67496144";
    actual = otp.codeForEpoch(100);
    if (!expected.equals(actual)) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    } else {
      return true;
    }
  }

  (:test)
  function TestOtpSha256_6digits(logger as Test.Logger) {
    var key = "12345678901234567890";
    var otp = new Totp(key.toUtf8Array(), 1, 6, 30);
    var expected = "190188";
    var actual = otp.codeForEpoch(0x0000000003561b69 * 30);
    if (!expected.equals(actual)) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    } else {
      return true;
    }
  }

  (:test)
  function TestHotp(logger as Test.Logger) {
    var key = "12345678901234567890";
    var hotp = new Hotp(key.toUtf8Array(), 0, 8, null);
    
    // Test vectors from RFC 4226
    var expected = "755224";
    hotp.setCounter(0);
    var actual = hotp.code();
    if (!expected.equals(actual.subStringUTF8(2, 6))) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    }

    expected = "287082";
    hotp.setCounter(1);
    actual = hotp.code();
    if (!expected.equals(actual.subStringUTF8(2, 6))) {
      logger.debug(
        Lang.format("Expected: '$1$', actual: '$2$'", [expected, actual])
      );
      return false;
    }

    return true;
  }
}
