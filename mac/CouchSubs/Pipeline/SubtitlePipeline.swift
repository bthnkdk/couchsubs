// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CouchSubsCore
import Foundation

/// Altyazıları TV'ye ileten taraf (gerçekte `SubtitleServer`).
protocol SubtitleSending: AnyObject {
    /// `box`: oyundaki altyazının karedeki yeri (kenarlara oranla), bilinmiyorsa nil.
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?)
    func clear()
}

extension SubtitleServer: SubtitleSending {}

/// Kare → bölge → yazı tanıma → kararlılık → çeviri → TV.
@MainActor
final class SubtitlePipeline {
    /// Satır ekrandan bundan uzun süre önce kalktıysa geç gelen çevirisi gösterilmez (sonraki sahnenin üstüne düşmesin).
    static let lateResultMs = 1000
    private static let rememberedPairs = 8

    /// Bir çeviri isteği; satır ekrandan kalkınca `leftAt` not edilir.
    private final class Request {
        let number: Int
        let source: String
        let box: TextBox?
        let session: Int
        /// Satırın ekrandan kalktığı an (hâlâ ekrandaysa nil).
        var leftAt: Int?
        init(number: Int, source: String, box: TextBox?, session: Int) {
            self.number = number
            self.source = source
            self.box = box
            self.session = session
        }
    }

    private let reader: TextReader
    private let translator: TextTranslator
    private let server: SubtitleSending
    private let now: () -> Int
    private var stabilizer: SubtitleStabilizer
    private var scheduler: ReadScheduler
    /// Her çeviri isteği sıra numarası alır. Aynı anda yalnız bir çeviri sürer, bir tane de sırada bekler (en yenisi):
    /// hızlı konuşmada araya giren satırlar atlanır, kuyruk konuşma hızıyla büyümez.
    private var lastRequested = 0
    private var lastShown = 0
    private var inFlight: Request?
    private var pending: Request?
    private var pump: Task<Void, Never>?
    /// Süren çevirinin kendisi; okuma durunca iptal edilir.
    private var work: Task<String, Error>?
    /// Şu an oyun ekranında duran satırın numarası (bölge boşalınca nil).
    private var lineOnScreen: Int?
    /// Son çevrilen satırlar (kaynak → çeviri; zaten hedef dildeyse nil). Geri gelen satır bunlardan yeniden gösterilir.
    private var pairs: [(number: Int, source: String, translation: String?)] = []
    /// Okuma durdurulunca artar; önceki oturumdan dönen çeviriler gösterilmez.
    private var session = 0
    /// Son okunan satırlar; kare değişmediyse yeniden okunmaz, bunlar kullanılır.
    private var lastReading = Reading.empty

    private(set) var lastPair: (source: String, translation: String)?
    /// Son gösterilen çevirinin oyundaki altyazının yeri.
    private(set) var lastBox: TextBox?
    private(set) var lastError: TranslatorError?
    var onPair: ((String, String) -> Void)?
    /// TV'ye giden her yeni altyazının seslendirilecek cümleleri (dublaj).
    var onSpeech: (([SpokenLine]) -> Void)?
    /// Her yazı tanıma denemesinden sonra çağrılır (başarılıysa nil). Disk dolunca macOS okumayı hep hata ile bitirir.
    var onReadResult: ((Error?) -> Void)?
    /// Her çeviri denemesinden sonra çağrılır (başarılıysa nil).
    var onTranslationResult: ((TranslatorError?) -> Void)?
    /// Oyun paketi: kararlı satırın hazır Türkçesi (yoksa nil). Çeviri motorundan ve önbellekten önce bakılır; bulunursa
    /// motor hiç çağrılmaz ve çeviri beklemeden gösterilir. Uygulama paketler açıkken verir.
    var packLookup: ((String) -> PackMatch?)?
    /// Hiçbir pakette bulunmayan kararlı satır (ortak havuz için).
    var onPackMiss: ((String) -> Void)?
    /// Son gösterilen çevirinin nereden geldiği: "paket" ya da "motor" (günlük ve sayım için).
    private(set) var lastOrigin: String?
    /// Bu hatta paketten gelen satır sayısı.
    private(set) var packHits = 0

    /// `scheduler`: varsayılanı her kareyi okur; uygulama gereksiz okumaları atlayan planı verir.
    /// `clock`: milisaniye saati; testlerde sahtesi verilir.
    init(reader: TextReader, translator: TextTranslator, server: SubtitleSending, scheduler: ReadScheduler = .always,
         clock: @escaping () -> Int = SubtitleStabilizer.uptimeMs) {
        self.reader = reader
        self.translator = translator
        self.server = server
        self.scheduler = scheduler
        self.now = clock
        self.stabilizer = SubtitleStabilizer(clock: clock)
    }

    /// Okuma çeviriyi beklemez; böylece çeviri sürerken gelen satırlar da yakalanır.
    func process(_ frame: CGImage, region: CropRegion) async {
        // Yazı tanıma uzun sürebilir; arayüz takılmasın diye ana iş parçacığının dışında yapılır.
        let reader = self.reader
        let (area, signature) = await Task.detached(priority: .userInitiated) {
            let area = RegionCropper.crop(frame, to: region)
            return (area, RegionCropper.signature(of: area))
        }.value
        switch scheduler.plan(signature: signature) {
        case .reuse:
            break
        case .read(let deep):
            let result = await Task.detached(priority: .userInitiated) {
                Result { try reader.readLines(area, deep: deep) }
            }.value
            lastReading = (try? result.get()) ?? .empty
            onReadResult?(result.failure)
            scheduler.record(lastReading.text)
        }
        // Kumanda ipuçları ("R2 Swing") altyazı değildir; çevrilmez, yeri de altyazının yerine katılmaz.
        // Yazı tanımanın uydurduğu sözcük çöpleri ("ou$3e") de çevirmene gitmez.
        // Alandaki menü ve köşe göstergeleri de altyazı değildir; yalnız altyazı bloğu çevrilir ve kutusu ona göre olur.
        let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        let reading = lastReading.withoutButtonPrompts().withoutOcrNoise().subtitleBlock(in: place)
        let box = reading.box?.placed(in: place).centeredOnScreen()
        switch stabilizer.feed(reading.text) {
        case .none:
            break
        case .clear:
            lineLeft()
            server.clear()
        case .translate(let source):
            lineLeft()
            enqueue(source, box: box)
        case .restore(let source):
            lineLeft()
            restore(source, box: box)
        }
    }

    /// Ekrandaki satır kalktı (ya da yerine başkası geldi); çevirisi sürüyorsa ne zaman kalktığı not edilir.
    private func lineLeft() {
        guard let number = lineOnScreen else { return }
        let time = now()
        for request in [inFlight, pending] where request?.number == number && request?.leftAt == nil {
            request?.leftAt = time
        }
        lineOnScreen = nil
    }

    private func enqueue(_ source: String, box: TextBox?) {
        lastRequested += 1
        let request = Request(number: lastRequested, source: source, box: box, session: session)
        lineOnScreen = request.number
        if let packed = packLookup?(source) {
            showPacked(request, packed)
            return
        }
        onPackMiss?(source)
        // Çeviri sürüyorsa yeni satır sıraya girer; sıradaki eski satır atlanır (artık ekranda değil).
        guard inFlight == nil else {
            pending = request
            return
        }
        inFlight = request
        pump = Task { [weak self] in await self?.runPump() }
    }

    /// Paketteki Türkçe hemen gösterilir; süren çevirinin sonucu (eski satır) artık gösterilmez.
    private func showPacked(_ request: Request, _ packed: PackMatch) {
        pending = nil
        packHits += 1
        let source = request.source
        let translated = packed.text
        let shouldSend = stabilizer.shouldSend(source: source, translation: translated)
        remember(request.number, source, shouldSend ? translated : nil)
        guard shouldSend else { return }
        lastShown = request.number
        server.sendSubtitle(translated, durationMs: 15000, box: request.box)
        lastPair = (source, translated)
        lastBox = request.box
        lastOrigin = "paket"
        onPair?(source, translated)
        onSpeech?(packed.spoken)
    }

    /// Az önce kalkıp geri gelen satır: çevirmene gitmeden eski çevirisi yeniden gösterilir.
    private func restore(_ source: String, box: TextBox?) {
        if let pair = pairs.last(where: { $0.source == source }) {
            lineOnScreen = pair.number
            guard let translation = pair.translation else { return }
            server.sendSubtitle(translation, durationMs: 15000, box: box)
            lastPair = (source, translation)
            lastBox = box
            return
        }
        // Çevirisi henüz gelmediyse istek sürüyordur; satır yeniden ekranda sayılır.
        for case let request? in [inFlight, pending] where request.source == source && request.session == session {
            request.leftAt = nil
            lineOnScreen = request.number
            return
        }
        // Çevirisi hiç yoksa (atlanmış ya da başarısız olmuş) normal yoldan çevrilir.
        enqueue(source, box: box)
    }

    /// Süren çeviriyi, bitince de sıradakini çevirir; sıra boşalınca durur.
    private func runPump() async {
        while let request = inFlight {
            await translate(request)
            var next = pending
            pending = nil
            // Ekrandan çoktan kalkmış satır çevrilmez; çevirisi zaten gösterilmeyecekti.
            if let candidate = next, candidate.session != session || candidate.leftAt.map({ now() - $0 > Self.lateResultMs }) == true {
                next = nil
            }
            inFlight = next
        }
    }

    /// Süren bütün çevirilerin bitmesini bekler.
    func waitForTranslations() async {
        while inFlight != nil, let pump { await pump.value }
    }

    /// Satır ekrandan kalktıktan sonra gelen çevirinin TV'de kalacağı süre (TV uygulamasıyla aynı kural).
    static func readingTime(for text: String) -> Int {
        min(8000, 2000 + text.count * 60)
    }

    private func translate(_ request: Request) async {
        let source = request.source
        do {
            let translator = self.translator
            let work = Task { try await translator.translate(source) }
            self.work = work
            defer { self.work = nil }
            let translated = try await work.value
            guard request.session == session else { return }
            lastError = nil
            onTranslationResult?(nil)
            let shouldSend = stabilizer.shouldSend(source: source, translation: translated)
            remember(request.number, source, shouldSend ? translated : nil)
            guard request.number > lastShown, shouldSend else { return }
            let onScreen = request.number == lineOnScreen
            // Satır ekrandan çoktan kalktıysa çevirisi sonraki sahnenin üstüne düşmesin.
            if !onScreen, let left = request.leftAt, now() - left > Self.lateResultMs { return }
            lastShown = request.number
            // Satır hâlâ ekrandaysa kalkınca silinir; kalktıysa okunacak kadar gösterilir.
            server.sendSubtitle(translated, durationMs: onScreen ? 15000 : Self.readingTime(for: translated), box: request.box)
            lastPair = (source, translated)
            lastBox = request.box
            lastOrigin = "motor"
            onPair?(source, translated)
            if let onSpeech { onSpeech(translator.spokenLines(for: source)) }
        } catch {
            guard request.session == session else { return }
            // Dil paketi eksikse ya da geçici bir hata olduysa satır ekranda kaldıkça (saniyede en çok bir kez) yeniden denenir.
            lastError = error as? TranslatorError
            onTranslationResult?(lastError)
            if request.number == lineOnScreen { stabilizer.forgetSent() }
        }
    }

    private func remember(_ number: Int, _ source: String, _ translation: String?) {
        pairs.removeAll { $0.source == source }
        pairs.append((number, source, translation))
        if pairs.count > Self.rememberedPairs { pairs.removeFirst() }
    }

    /// Okumanın hemen başlaması için modelleri önceden yükler; ilk okuma yoksa saniyelerce sürer.
    func warmUp() {
        let reader = self.reader
        Task.detached(priority: .utility) {
            let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            if let image = context?.makeImage() { _ = try? reader.read(image) }
        }
        let translator = self.translator
        Task { _ = try? await translator.translate("Hello") }
    }

    /// Okuma durunca TV'deki son altyazıyı kaldırır.
    func reset() {
        session += 1
        lineOnScreen = nil
        pending = nil
        // Apple'ın çevirisi görev iptaline uyar; süren çeviri beklenmeden bırakılır.
        work?.cancel()
        pairs.removeAll()
        lastReading = .empty
        scheduler.reset()
        if stabilizer.reset() == .clear { server.clear() }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
