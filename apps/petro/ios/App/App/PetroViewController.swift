import UIKit
import Capacitor

/// يسجّل إضافة الويدجت المحلية (ليست في حزمة SPM) مع جسر Capacitor.
class PetroViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(ShiftWidgetPlugin())
    }
}
