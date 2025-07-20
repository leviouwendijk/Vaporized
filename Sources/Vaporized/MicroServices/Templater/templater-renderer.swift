import Foundation
import Structures
import Surfaces
import Interfaces
import plate

public enum TemplaterTemplateRenderingError: Error, LocalizedError, Sendable {
    case unsupportedReturnType(template: String, type: String)
    case missingPlaceholder(name: String)
    case invalidPlaceholderType(name: String, expected: TemplaterPlaceholderType, actual: JSONValue)
    case unresolvedPlaceholders(raw: [String], place: String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedReturnType(let tpl, let type):
            return "Template '\(tpl)' does not support return type '\(type)'."
        case .missingPlaceholder(let name):
            return "Required placeholder '\(name)' was not provided."
        case .invalidPlaceholderType(let name, let expected, let actual):
            return "Placeholder '\(name)' expected type \(expected.rawValue), but got \(actual)."
        case .unresolvedPlaceholders(let raw, let place):
            return "Unresolved placeholders still in \(place): \(raw.joined(separator: ", "))."
        }
    }
}

public struct TemplaterTemplateRenderer: Sendable {
    private let provider:      TemplaterTemplateProviding
    private let configLoader:  TemplaterConfigurationLoading
    private let imageProvider:      TemplaterImageProviding
    private let pdfRenderer:   PDFRenderable
    private let placeholderSyntax: PlaceholderSyntax
    private let resourcesURL: URL

    public init(
        provider:           TemplaterTemplateProviding,
        configLoader:       TemplaterConfigurationLoading,
        imageProvider:      TemplaterImageProvider,
        pdfRenderer:        PDFRenderable = WeasyPrintRenderer(),
        placeholderSyntax:  PlaceholderSyntax = PlaceholderSyntax(prepending: "{{", appending: "}}"),
        resourcesURL: URL
    ) {
        self.provider          = provider
        self.configLoader      = configLoader
        self.imageProvider     = imageProvider
        self.pdfRenderer       = pdfRenderer
        self.placeholderSyntax = placeholderSyntax
        self.resourcesURL = resourcesURL
    }

    public func render(request: TemplaterRenderRequest) -> TemplaterRenderResponse {
        do {
            let cfg = try loadAndValidateConfig(request)

            var (vars, reps) = try buildProvidedReplacements(from: request.variables, config: cfg)

            try applyDynamicReplacements(
                placeholders: cfg.placeholders.rendered,
                into: &vars,
                reps: &reps,
                config: cfg
            )

            let raw        = try provider.fetchTemplate(at: request.template)
            let subject    = try interpolateSubjectIfNeeded(cfg.subject, with: reps)
            let filled     = interpolateTemplate(raw, with: reps)
            let styled     = try injectCSS(into: filled, cssURL: request.template.cssURL(resourcesURL: resourcesURL))

            let withImages = try applyImagePlaceholders(
                to: styled,
                config: cfg
            )
            // let rendered = embedImages(in: styled, imageDir: resourcesURL.appendingPathComponent("Images"))

            let final = try finalize(withImages, returning: request.returning)
            return .init(success: true, subject: subject, use: cfg.use, text: final.text, html: final.html, base64: final.base64, error: nil)

        } catch {
            return .init(success: false, subject: nil, use: nil, text: nil, html: nil, base64: nil, error: error.localizedDescription)
        }
    }

    private func loadAndValidateConfig(_ request: TemplaterRenderRequest) throws -> TemplaterTemplateConfiguration {
        let cfg = try configLoader.loadConfig(for: request.template)
        guard cfg.allowedReturnTypes?.contains(request.returning) ?? true else {
            throw TemplaterTemplateRenderingError.unsupportedReturnType(template: request.template.basePath, type: request.returning.rawValue)
        }
        return cfg
    }

    private func buildProvidedReplacements(
        from variables: [String: JSONValue],
        config: TemplaterTemplateConfiguration
    ) throws -> (vars: [String: JSONValue], reps: [StringTemplateReplacement]) {
        var reps: [StringTemplateReplacement] = []
        let vars = variables

        for spec in config.placeholders.provided {
            let name = spec.placeholder
            guard let value = vars[name] else {
                if spec.required {
                    throw TemplaterTemplateRenderingError.missingPlaceholder(name: name)
                }
                continue
            }

            switch value {
            case .string, .int, .double, .bool:
                let token   = placeholderSyntax.set(for: name)
                let literal = try value.stringValue
                reps.append(
                  StringTemplateReplacement(
                    placeholders:     [token],
                    replacement:      literal,
                    initializer:      .manual,
                    placeholderSyntax: placeholderSyntax
                  )
                )
            default:
                // arrays/objects/null: leave in `vars` for dynamic rendering
                break
            }
        }

        return (vars, reps)
    }

    private func applyDynamicReplacements(
        placeholders: [TemplaterRenderedPlaceholder],
        into vars: inout [String: JSONValue],
        reps: inout [StringTemplateReplacement],
        config: TemplaterTemplateConfiguration
    ) throws {
        for spec in placeholders {
            // 1) extract JSONValue inputs
            let inputs = try spec.using.map { key in
                guard let v = vars[key] else {
                    throw TemplaterDynamicRenderingError.missingProvidedValue(name: key)
                }
                return v
            }
            // 2) dispatch
            let ctor = spec.constructor
            let dynRep = try ctor.render(
                placeholder: spec.placeholder,
                using:             Dictionary(uniqueKeysWithValues: zip(spec.using, inputs)),
                config:            config,
                syntax:            placeholderSyntax
            )
            // 3) register
            reps.append(dynRep)
            vars[spec.placeholder] = .string(dynRep.replacement)
        }
    }

    private func applyImagePlaceholders(
        to html: String,
        config: TemplaterTemplateConfiguration
    ) throws -> String {
        var out = html

        for imgSpec in config.images {
            let token = placeholderSyntax.set(for: imgSpec.placeholder)
            // call your isolated func, handing it the same provider
            let rep = try renderImageNode(
                placeholder: imgSpec.placeholder,
                baseURL:     resourcesURL.appendingPathComponent("Images"),
                config:      config,
                syntax:      placeholderSyntax,
                imageProvider: imageProvider
            )
            // do a one-to-one replace of the placeholder
            out = out.replacingOccurrences(of: token, with: rep.replacement)
        }

        return out
    }

    private func interpolateSubjectIfNeeded(
        _ subjectTpl: String?,
        with reps:        [StringTemplateReplacement]
    ) throws -> String? {
        guard let s = subjectTpl else { return nil }
        let out = StringTemplateConverter(text: s, replacements: reps).replace(replaceEmpties: false)
        let unresolved = out.extractingRawTemplatePlaceholderSyntaxes()
        guard unresolved.isEmpty else {
            throw TemplaterTemplateRenderingError.unresolvedPlaceholders(raw: unresolved, place: "subject")
        }
        return out
    }

    private func interpolateTemplate(
        _ raw: String,
        with reps: [StringTemplateReplacement]
    ) -> String {
        return StringTemplateConverter(text: raw, replacements: reps).replace(replaceEmpties: false)
    }

    private func finalize(
        _ html: String,
        returning ret: DocumentExtensionType
    ) throws -> (text: String?, html: String?, base64: String?) {
        var text:     String?
        var outHtml:String?
        var b64:        String?

        switch ret {
        case .html:
            outHtml = html
        case .pdf:
            let dest = NSTemporaryDirectory()+UUID().uuidString+".pdf"
            try html.weasyPDF(destination: dest, encoding: .utf8)
            let data = try Data(contentsOf: URL(fileURLWithPath: dest))
            b64 = data.base64EncodedString()
        default:
            text = html
        }
        if b64 == nil { b64 = Data(html.utf8).base64EncodedString() }
        return (text, outHtml, b64)
    }
}
