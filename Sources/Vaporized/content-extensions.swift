import Surfaces
import Structures
import Vapor
import plate

// library: Structures
extension FieldValue: @retroactive Content { }
extension JSONValue: @retroactive Content { }

// surface: Dataman
extension DatamanRequest: @retroactive Content { }
extension DatamanResponse: @retroactive Content { }

// surface: Captcher
extension CaptcherTokenType: @retroactive Content {}
extension CaptcherOperation: @retroactive Content {}
extension CaptcherRequest: @retroactive Content {}
extension CaptcherResponse: @retroactive Content {}
extension CaptcherValidationResult: @retroactive Content {}
extension CaptcherValidateBody: @retroactive Content {}
extension CaptcherThresholdMetric: @retroactive Content {}
extension CaptcherThresholdEvaluationResult: @retroactive Content {}
extension CaptcherMetricEvaluation: @retroactive Content {}
extension CaptcherMetrics: @retroactive Content {}

// surface: Templater
extension TemplaterUseDesignation: @retroactive Content { }
extension TemplaterSection:   @retroactive Content { }
extension TemplaterPlatform:   @retroactive Content { }
extension TemplaterGroup:      @retroactive Content { }
extension TemplaterType:       @retroactive Content { }
extension TemplaterVariant:    @retroactive Content { }
extension TemplaterPlaceholderType: @retroactive Content { }
extension TemplaterPlaceholders:     @retroactive Content { }
extension TemplaterProvidedPlaceholder:     @retroactive Content { }
extension TemplaterRenderedPlaceholder:     @retroactive Content { }
extension TemplaterTemplatePath:           @retroactive Content { }  // :contentReference[oaicite:0]{index=0}
extension TemplaterTemplateConfiguration:  @retroactive Content { }  // :contentReference[oaicite:1]{index=1}
extension TemplaterTemplate:               @retroactive Content { }  // :contentReference[oaicite:2]{index=2}
extension TemplaterRenderRequest:  @retroactive Content { }  // :contentReference[oaicite:3]{index=3}
extension TemplaterRenderResponse: @retroactive Content { }  // :contentReference[oaicite:4]{index=4}

// plate: --- referenced by Templater models
extension DocumentExtensionType: @retroactive Content { }
extension LanguageSpecifier:      @retroactive Content { }
