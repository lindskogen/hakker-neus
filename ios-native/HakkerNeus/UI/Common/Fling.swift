import UIKit

/// Where a swipe let go at `velocity` (points per second) comes to rest if it coasts on, slowing
/// like a scroll view at `rate`. Swipes decide by this whether they were flung far enough, the way
/// Apple recommends ("Designing Fluid Interfaces", WWDC 2018), rather than by a speed limit.
func projectedPosition(
    _ position: CGFloat,
    velocity: CGFloat,
    rate: UIScrollView.DecelerationRate = .normal
) -> CGFloat {
    let r = rate.rawValue
    return position + velocity / 1000 * r / (1 - r)
}
