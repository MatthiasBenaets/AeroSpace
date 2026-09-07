import Common

extension Workspace {
    @MainActor func normalizeContainers() {
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableNormalizationBinaryTree {
            // BSP mode: normalize each container so that a new split will go along
            // the longest dimension of that container's rect. This ensures the tree
            // stays binary and orientations follow aspect ratios without restructuring
            // the entire tree globally (which would cause cascading re-layouts).
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
                // Single child keeps the parent's rect (no split yet)
                for child in children {
                    (child as? TilingContainer)?.normalizeBinaryTree(rect: rect)
                }
            default:
                // Multiple children: split along this container's orientation
                let childRects = rect.sliced(along: orientation, weights: children.map { $0.getWeight(orientation) })
                for (index, child) in children.enumerated() {
                    (child as? TilingContainer)?.normalizeBinaryTree(rect: childRects[index])
                }
        }
    }
}
