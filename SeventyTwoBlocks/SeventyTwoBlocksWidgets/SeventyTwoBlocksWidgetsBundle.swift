import WidgetKit
import SwiftUI

@main
struct SeventyTwoBlocksWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CurrentBlockWidget()
        BlockGridWidget()
        LockScreenCircularWidget()
        LockScreenRectangularWidget()
        TimerLiveActivity()
    }
}
