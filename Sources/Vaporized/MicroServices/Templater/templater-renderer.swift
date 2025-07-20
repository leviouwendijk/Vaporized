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

    // public func render(request: TemplaterRenderRequest) -> TemplaterRenderResponse {
    //     let path  = request.template
    //     let tplId = path.basePath

    //     do {
    //         let cfg = try configLoader.loadConfig(for: path)

    //         if let allowed = cfg.allowedReturnTypes,
    //             !allowed.contains(request.returning) {
    //                 throw TemplaterTemplateRenderingError.unsupportedReturnType(
    //                     template: tplId,
    //                     type: request.returning.rawValue
    //                 )
    //         }

    //         if let specs = cfg.placeholders {
    //             for spec in specs where spec.required {
    //                 guard let value = request.variables[spec.placeholder] else {
    //                     throw TemplaterTemplateRenderingError.missingPlaceholder(name: spec.placeholder)
    //                 }
    //                 if let expected = spec.type {
    //                     switch (expected, value) {
    //                     case (.integer, .int),
    //                          (.double,  .double),
    //                          (.string,  .string),
    //                          (.object,  .object):
    //                         break
    //                     default:
    //                         throw TemplaterTemplateRenderingError.invalidPlaceholderType(
    //                           name: spec.placeholder,
    //                           expected: expected,
    //                           actual: value
    //                         )
    //                     }
    //                 }
    //             }
    //         }

    //         let raw = try provider.fetchTemplate(at: path)

    //         let replacements = request.variables.map { key, jsonValue -> StringTemplateReplacement in
    //             let placeholder = placeholderSyntax.set(for: key)
    //             let valueString = (try? jsonValue.stringValue) ?? ""
    //             return StringTemplateReplacement(
    //                 placeholders: [placeholder],
    //                 replacement:  valueString,
    //                 initializer:  .manual,
    //                 placeholderSyntax: placeholderSyntax
    //             )
    //         }

    //         let subject: String?
    //         if let templateSubject = cfg.subject {
    //             subject = StringTemplateConverter(
    //                 text:         templateSubject,
    //                 replacements: replacements
    //             ).replace(replaceEmpties: false)
    //         } else {
    //             subject = nil
    //         }

    //         if let newSub = subject {
    //             let rawSubjectPlaceholders = newSub.extractingRawTemplatePlaceholderSyntaxes()
    //             if !rawSubjectPlaceholders.isEmpty {
    //                 throw TemplaterTemplateRenderingError.unresolvedPlaceholders(raw: rawSubjectPlaceholders, place: "subject")
    //             }
    //         }

    //         let converter = StringTemplateConverter(
    //             text:         raw,
    //             replacements: replacements
    //         )
    //         let filled = converter.replace(replaceEmpties: false)

    //         let styled = try injectCSS(
    //             into: filled,
    //             platform: path.platform,
    //             resources: resourcesURL
    //         )

    //         let imageDir = resourcesURL.appendingPathComponent("Images")
    //         let rendered = embedImages(
    //             in: styled, 
    //             imageDir: imageDir
    //         )

    //         let rawPlaceholders = rendered.extractingRawTemplatePlaceholderSyntaxes()
    //         if !rawPlaceholders.isEmpty {
    //             throw TemplaterTemplateRenderingError.unresolvedPlaceholders(raw: rawPlaceholders, place: "template text")
    //         }

    //         var textOutput: String?
    //         var htmlOutput: String?
    //         var base64Output: String?

    //         switch request.returning {
    //         case .html:
    //             htmlOutput = rendered
    //         case .pdf:
    //             let pdfDest = NSTemporaryDirectory() + UUID().uuidString + ".pdf"

    //             try rendered.weasyPDF(
    //                 destination: pdfDest,
    //                 encoding: .utf8
    //             )

    //             let pdfData = try Data(contentsOf: URL(fileURLWithPath: pdfDest))
    //             base64Output = pdfData.base64EncodedString()
    //         default:
    //             textOutput = rendered
    //         }

    //         if base64Output == nil {
    //             base64Output = Data(rendered.utf8).base64EncodedString()
    //         }

    //         return TemplaterRenderResponse(
    //             success: true,
    //             subject: subject,
    //             use: cfg.use,
    //             text:   textOutput,
    //             html:   htmlOutput,
    //             base64: base64Output,
    //             error:  nil
    //         )
    //     } catch {
    //         return TemplaterRenderResponse(
    //             success: false,
    //             subject: nil,
    //             use:    nil,
    //             text:   nil,
    //             html:   nil,
    //             base64: nil,
    //             error:  error.localizedDescription
    //         )
    //     }
    // }

    public func render(request: TemplaterRenderRequest) -> TemplaterRenderResponse {
        do {
            let cfg = try loadAndValidateConfig(request)

            // 1) seed with “provided” placeholders
            var (vars, reps) = try buildProvidedReplacements(from: request.variables, config: cfg)

            // 2) generate all dynamic placeholders
            try applyDynamicReplacements(
                placeholders: cfg.placeholders.rendered,
                into:                &vars,
                reps:                 &reps,
                config:             cfg
            )

            // 3) fetch, fill and post‐process
            let raw            = try provider.fetchTemplate(at: request.template)
            let subject    = try interpolateSubjectIfNeeded(cfg.subject, with: reps)
            let filled     = interpolateTemplate(raw, with: reps)
            let styled     = try injectCSS(into: filled, cssURL: request.template.cssURL(resourcesURL: resourcesURL))
            let rendered = embedImages(in: styled, imageDir: resourcesURL.appendingPathComponent("Images"))

            let final = try finalize(rendered, returning: request.returning)
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
