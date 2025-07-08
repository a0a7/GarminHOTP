import Toybox.WatchUi;

class OTPAuthInput extends WatchUi.BehaviorDelegate {
  private var otpView as OTPAuthView;

  function initialize(view as OTPAuthView) {
    BehaviorDelegate.initialize();
    otpView = view;
  }

  function onSelect() {
    var otpCode = otpView.getCurrentOtpCode();
    if (otpCode != null && otpCode.isHotp()) {
      // For HOTP, generate next code on select
      otpCode.getOtp().code(); // This will increment the counter
      otpView.requestUpdate();
    } else {
      // For TOTP or multiple accounts, go to next account
      onNextPage();
    }
    return true;
  }

  function onNextPage() {
    if (WatchUi has :cancelAllAnimations) {
      WatchUi.cancelAllAnimations();
    }
    otpView.nextCode();
    return true;
  }

  function onPreviousPage() {
    if (WatchUi has :cancelAllAnimations) {
      WatchUi.cancelAllAnimations();
    }
    otpView.prevCode();
    return true;
  }
}
