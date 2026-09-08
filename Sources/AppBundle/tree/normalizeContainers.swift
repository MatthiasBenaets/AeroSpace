import Common

extension Workspace {
    @MainActor func normalizeContainers() {
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableNormalizationBinaryTree {
            // BSP mode: before orienting containers, find the container that previously
            // held the closing window and set the focus override to its remaining child.
            TilingContainer.findAndSetFocusOverride(rootTilingContainer)
            rootTilingContainer.normalizeBinaryTree(
                rect: workspaceMonitor.visibleRectPaddedByOuterGaps,
            )
        } else if config.enableNormalizationOppositeOrientationForNestedContainers {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && (child is TilingContainer || !isRootContainer) {
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            }
            if children.isEmpty && !isRootContainer {
                unbindFromParent()
            }
        }
    }

    // MARK: - BSP Focus Tracking

    /// During BSP normalization, tracks the window that should be focused after a
    /// window is removed. This is the sibling in the same container that grows
    /// into the freed space.
    @MainActor static var __bspFocusOverride: TreeNode?

    /// Parent container of the window being closed (captured before unbinding,
    /// by CloseCommand). Used during normalization to find the remaining child
    /// that grows into the freed space.
    @MainActor static var __bspClosingParent: TilingContainer?

    // MARK: - BSP Orientation Normalization

    /// Normalize BSP orientations locally: each container orients itself based on
    /// the aspect ratio of its available rect. Unlike forceBinaryTree, this only
    /// adjusts orientations — it never changes the tree structure. The tree shape
    /// is determined by the split command, not by normalization.
    @MainActor func normalizeBinaryTree(rect: Rect) {
        // Determine orientation from aspect ratio
        let newOrientation = rect.isLandscape ? Orientation.h : Orientation.v
        if orientation != newOrientation {
            _orientation = newOrientation
        }

        // Recurse: allocate rects proportionally by weight
        switch children.count {
            case 0, 1:
                // Single child keeps the parent's rect (no split yet).
                // The focus override (if set by findAndSetFocusOverride) will
                // already point to this child — no additional work needed here.
                for child in children {
                    (child as? TilingContainer)?.normalizeBinaryTree(rect: rect)
                }
            default:
                // Multiple children: split along this container's orientation.
                let childRects = rect.sliced(along: orientation, weights: children.map { $0.getWeight(orientation) })
                for (index, child) in children.enumerated() {
                    (child as? TilingContainer)?.normalizeBinaryTree(rect: childRects[index])
                }
        }
    }

    /// Find the focus override using the stored closing parent container.
    /// The remaining child of the closing parent is the one that grows into
    /// the freed space.
    @MainActor static func findAndSetFocusOverride(_ root: TilingContainer) {
        guard let closingParent = TilingContainer.__bspClosingParent else { return }
        // The closing parent is already in the tree (its child was just removed).
        // The remaining child should be focused.
        TilingContainer.__bspFocusOverride = closingParent.children.first
    }

}
