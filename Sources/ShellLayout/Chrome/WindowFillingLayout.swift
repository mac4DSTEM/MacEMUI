import SwiftUI

/// A single-child container that is exactly as large as the space it is
/// offered, whatever its child's minimum is (the child may overflow, topLeading).
/// A rigid child — `NavigationSplitView` pinning its columns after a sidebar
/// that could not grow the window — otherwise makes its parent, and so any
/// `.onGeometryChange` on it, report the child's width instead of the
/// window's. A finite proposal is answered with itself (so the window's
/// minimum comes from the frame above the window's root view, not from the split); an
/// ideal or unbounded query is answered by the child, so the window's ideal
/// and maximum sizes are unchanged.
public struct WindowFillingLayout: Layout {
    public init() {}

    public nonisolated static func reportedSize(proposal: ProposedViewSize, child: CGSize) -> CGSize {
        func axis(_ offered: CGFloat?, _ own: CGFloat) -> CGFloat {
            if let offered, offered.isFinite { return offered }
            return own
        }
        return CGSize(width: axis(proposal.width, child.width),
                      height: axis(proposal.height, child.height))
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.reportedSize(proposal: proposal,
                          child: subviews.first?.sizeThatFits(proposal) ?? .zero)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(bounds.size))
    }
}
