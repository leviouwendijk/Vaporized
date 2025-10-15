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

// extension CaptcherThresholdMetric: @retroactive Content {}
// extension CaptcherThresholdEvaluationResult: @retroactive Content {}
// extension CaptcherMetricEvaluation: @retroactive Content {}
extension CaptcherMetrics: @retroactive Content {}

extension CaptcherSignal: @retroactive Content {}
extension CaptcherRiskPolicy: @retroactive Content {}
extension CaptcherDecision: @retroactive Content {}
extension CaptcherSignalContribution: @retroactive Content {}
extension CaptcherRiskEvaluationResult: @retroactive Content {}

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
extension TemplaterTemplatePath:           @retroactive Content { }  
extension TemplaterTemplateConfiguration:  @retroactive Content { }  
extension TemplaterTemplate:               @retroactive Content { }  
extension TemplaterRenderRequest:  @retroactive Content { }  
extension TemplaterRenderResponse: @retroactive Content { }  

// plate: --- referenced by Templater models
extension DocumentExtensionType: @retroactive Content { }
extension LanguageSpecifier:      @retroactive Content { }
