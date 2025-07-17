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
    private let pdfRenderer:   PDFRenderable
    private let placeholderSyntax: PlaceholderSyntax
    private let resourcesURL: URL

    public init(
        provider:           TemplaterTemplateProviding,
        configLoader:       TemplaterConfigurationLoading,
        pdfRenderer:        PDFRenderable = WeasyPrintRenderer(),
        placeholderSyntax:  PlaceholderSyntax = PlaceholderSyntax(prepending: "{{", appending: "}}"),
        resourcesURL: URL
    ) {
        self.provider          = provider
        self.configLoader      = configLoader
        self.pdfRenderer       = pdfRenderer
        self.placeholderSyntax = placeholderSyntax
        self.resourcesURL = resourcesURL
    }

    public func render(request: TemplaterRenderRequest) -> TemplaterRenderResponse {
        let path  = request.template
        let tplId = path.basePath

        do {
            let cfg = try configLoader.loadConfig(for: path)

            if let allowed = cfg.allowedReturnTypes,
                !allowed.contains(request.returning) {
                    throw TemplaterTemplateRenderingError.unsupportedReturnType(
                        template: tplId,
                        type: request.returning.rawValue
                    )
            }

            if let specs = cfg.placeholders {
                for spec in specs where spec.required {
                    guard let value = request.variables[spec.placeholder] else {
                        throw TemplaterTemplateRenderingError.missingPlaceholder(name: spec.placeholder)
                    }
                    if let expected = spec.type {
                        switch (expected, value) {
                        case (.integer, .int),
                             (.double,  .double),
                             (.string,  .string),
                             (.object,  .object):
                            break
                        default:
                            throw TemplaterTemplateRenderingError.invalidPlaceholderType(
                              name: spec.placeholder,
                              expected: expected,
                              actual: value
                            )
                        }
                    }
                }
            }

            let raw = try provider.fetchTemplate(at: path)

            let replacements = request.variables.map { key, jsonValue -> StringTemplateReplacement in
                let placeholder = placeholderSyntax.set(for: key)
                let valueString = (try? jsonValue.stringValue) ?? ""
                return StringTemplateReplacement(
                    placeholders: [placeholder],
                    replacement:  valueString,
                    initializer:  .manual,
                    placeholderSyntax: placeholderSyntax
                )
            }

            let subject: String?
            if let templateSubject = cfg.subject {
                subject = StringTemplateConverter(
                    text:         templateSubject,
                    replacements: replacements
                ).replace(replaceEmpties: false)
            } else {
                subject = nil
            }

            if let newSub = subject {
                let rawSubjectPlaceholders = newSub.extractingRawTemplatePlaceholderSyntaxes()
                if !rawSubjectPlaceholders.isEmpty {
                    throw TemplaterTemplateRenderingError.unresolvedPlaceholders(raw: rawSubjectPlaceholders, place: "subject")
                }
            }

            let converter = StringTemplateConverter(
                text:         raw,
                replacements: replacements
            )
            let filled = converter.replace(replaceEmpties: false)

            let styled = try injectCSS(
                into: filled,
                platform: path.platform,
                resources: resourcesURL
            )

            let imageDir = resourcesURL.appendingPathComponent("Images")
            let rendered = embedImages(
                in: styled, 
                imageDir: imageDir
            )

            let rawPlaceholders = rendered.extractingRawTemplatePlaceholderSyntaxes()
            if !rawPlaceholders.isEmpty {
                throw TemplaterTemplateRenderingError.unresolvedPlaceholders(raw: rawPlaceholders, place: "template text")
            }

            var textOutput: String?
            var htmlOutput: String?
            var base64Output: String?

            switch request.returning {
            case .html:
                htmlOutput = rendered
            case .pdf:
                let pdfDest = NSTemporaryDirectory() + UUID().uuidString + ".pdf"

                try rendered.weasyPDF(
                    destination: pdfDest,
                    encoding: .utf8
                )

                let pdfData = try Data(contentsOf: URL(fileURLWithPath: pdfDest))
                base64Output = pdfData.base64EncodedString()
            default:
                textOutput = rendered
            }

            if base64Output == nil {
                base64Output = Data(rendered.utf8).base64EncodedString()
            }

            return TemplaterRenderResponse(
                success: true,
                subject: subject,
                text:   textOutput,
                html:   htmlOutput,
                base64: base64Output,
                error:  nil
            )
        } catch {
            return TemplaterRenderResponse(
                success: false,
                subject: nil,
                text:   nil,
                html:   nil,
                base64: nil,
                error:  error.localizedDescription
            )
        }
    }
}
