pkgname=battery-notify
pkgver=1.0.0
pkgrel=1
pkgdesc="A customizable, D-Bus driven battery notification daemon and CLI"
arch=('any')
url="https://github.com/YOUR_USERNAME/battery-notify" # Update this later
license=('GPL3') # Or 'MIT', depending on your preference
depends=('python' 'python-gobject' 'python-pydbus' 'libnotify' 'upower')
source=('battery-notify'
        'battery-notify.json'
        'battery-notify.service')
sha256sums=('SKIP'
            'SKIP'
            'SKIP')

package() {
    # Install the main Python executable
    install -Dm755 "$srcdir/battery-notify" "$pkgdir/usr/bin/battery-notify"
    
    # Install the default system-wide configuration
    install -Dm644 "$srcdir/battery-notify.json" "$pkgdir/etc/battery-notify.json"
    
    # Install the systemd user service
    install -Dm644 "$srcdir/battery-notify.service" "$pkgdir/usr/lib/systemd/user/battery-notify.service"
}