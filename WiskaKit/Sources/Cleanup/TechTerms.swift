import Foundation

/// English IT terms Swedish speakers mix in, which a Swedish recogniser mishears
/// ("puller-orchestern" for "pull requesten", "Gira" for "Jira"). Only used for Swedish.
enum TechTerms {
    /// Correct spellings, given to the model so it repairs toward them and never invents one.
    static let terms = ["deploy", "pipeline", "pull request", "merge", "branch", "commit", "code review",
                        "staging", "release", "runner", "cache", "refaktorera", "deprecated", "endpoint",
                        "frontend", "backend", "API", "Jira", "Kubernetes", "Docker", "Redis", "Datadog",
                        "AWS", "Azure AD", "Elasticsearch", "Slack", "GitHub Actions", "memory leak",
                        "timeout", "feature branch", "standup", "onboarding", "Postgres", "MySQL", "query",
                        "Terraform", "load balancer", "gateway", "Grafana", "Kafka", "consumer", "rollback",
                        "hotfix", "Sentry", "Confluence", "dashboard", "linter", "CI", "unit test", "Teams"]

    /// The term words the cleanup guard lets the model write in place of a misheard word.
    static let words: Set<String> = Set(terms.flatMap { $0.lowercased().split(separator: " ").map(String.init) })

    /// The prompt line. No misspelled examples: a model copies them ("deplåja") into correct text.
    static let promptLine = """
    The speaker works in IT and mixes in English technical terms, which speech recognition sometimes \
    mishears. If a word is clearly a misheard IT term, write the term correctly and keep its Swedish ending \
    ("pull requesten", "Kubernetes-klustret"). Terms they use include: \(terms.joined(separator: ", ")). \
    Correct English terms stay English and Swedish words stay Swedish.
    """

    /// "requesten", "kubernetes", "jira": an output word built from a term word plus a Swedish ending.
    static func isTermWord(_ word: String) -> Bool {
        words.contains { term in term.count >= 3 ? word.hasPrefix(term) && word.count <= term.count + 4 : word == term }
    }
}
