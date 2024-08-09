//
//  ViewController.swift
//  fastscroll-uicollectionview
//
//  Created by Vova on 31.07.2024.
//

import UIKit

final class ImageGridViewController: UIViewController {
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var collectionView: UICollectionView!

    private lazy var originalImage: UIImage = {
        let path = Bundle.main.path(forResource: "IMG_8526", ofType: "HEIC")!
        return UIImage(contentsOfFile: path)!
    }()

    private let thumbnailCache = NSCache<NSString, UIImage>()

    private let itemCount = 10000
    private let columnCount = 4
    private let spacing: CGFloat = 2.0
    private let originalImageAspectRatio = 0.75
    private var tileSize: CGFloat!
    private let thumbnailQueue = DispatchQueue(label: "com.thumbnail-generation", qos: .userInitiated, attributes: .concurrent)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        setInitialData()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        tileSize = calculateTileSize()
    }

    private func calculateTileSize() -> CGFloat {
        let totalWidth = CGRectGetWidth(view.bounds)
        let horizontalSpacingsCount = columnCount - 1
        let totalHorizontalSpacing = spacing * CGFloat(horizontalSpacingsCount)
        return round((totalWidth - totalHorizontalSpacing) / CGFloat(columnCount))
    }

    private lazy var scale: CGFloat = view.window!.windowScene!.screen.scale
}

extension ImageGridViewController {
    private func configureHierarchy() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self

        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ImageCell, Int> { cell, indexPath, postID in }

        dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            collectionView, indexPath, identifier in

            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: identifier)
        }
    }

    private func setInitialData() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        let items = Array(0...itemCount)
        snapshot.appendItems(items, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func getCachedThumbnail(at index: Int) -> UIImage? {
        let stringIndex = String(index) as NSString
        return thumbnailCache.object(forKey: stringIndex as NSString)
    }

    private func setCachedThumbnail(_ thumbnail: UIImage, at index: Int) {
        let stringIndex = String(index) as NSString
        thumbnailCache.setObject(thumbnail, forKey: stringIndex)
    }
}

extension ImageGridViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? ImageCell else { return }

        let itemIndex = (indexPath.row * columnCount) + indexPath.item
        if let cachedImage = getCachedThumbnail(at: itemIndex) {
            cell.configure(with: cachedImage)
        } else {
            let thumbnailWidth = Int(tileSize!) * Int(scale)
            let thumbnailHeight = Int(tileSize! / originalImageAspectRatio) * Int(scale)
            prepareThumbnail(image: originalImage, targetWidth: thumbnailWidth, targetHeight: thumbnailHeight) { [weak self] thumbnail in
                guard let self else { return }
                guard let thumbnail else { return }
                setCachedThumbnail(thumbnail, at: itemIndex)
                DispatchQueue.main.async {
                    cell.configure(with: thumbnail)
                }
            }
        }
    }
}

extension ImageGridViewController {

    private func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self else { return nil }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(tileSize),
                heightDimension: .fractionalHeight(1.0)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(tileSize)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columnCount
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            return section
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()

        return UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider,
            configuration: config
        )
    }

    private func prepareThumbnail(image: UIImage, targetWidth: Int, targetHeight: Int, completion: @escaping (_ thumbnail: UIImage?) -> Void) {
        thumbnailQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let cgImage = originalImage.cgImage!
            let thumbnailBytesPerRow = 4 * targetHeight
            guard let context = CGContext(
                data: nil,
                width: targetHeight,
                height: targetWidth,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: thumbnailBytesPerRow,
                space: cgImage.colorSpace!,
                bitmapInfo: cgImage.alphaInfo.rawValue
            ) else {
                completion(nil)
                return
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetHeight, height: targetWidth))
            let thumbnailCGImage = context.makeImage()!
            let thumbnail = UIImage(cgImage: thumbnailCGImage, scale: scale, orientation: image.imageOrientation)
            completion(thumbnail)
        }
    }
}
