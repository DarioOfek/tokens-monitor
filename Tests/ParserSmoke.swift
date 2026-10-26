import Foundation

@main
struct ParserSmoke {
    static func main() {
        let claude = """
        Usage
        Current session
        Resets in 4 hr 2 min
        35% used
        Weekly limits
        All models
        Resets Mon 7:00 AM
        4% used
        Limit resets
        """
        let grok = """
        Billing & invoices
        Current plan
        Premium
        97% used
        Weekly included usage · Resets Oct 31
        Account balance
        $0.03 used this month
        Credits available
        $20.00
        Payment details
        """
        precondition(AccountPageParser.parse(.anthropic, text: claude)?.limits.map(\.usedPercent) == [35, 4])
        precondition(AccountPageParser.parse(.xAI, text: grok)?.limits.first?.usedPercent == 97)
        precondition(AccountPageParser.parse(.xAI, text: grok)?.limits.first?.resetDescription == "Resets Oct 31")
        precondition(AccountPageParser.parse(.xAI, text: grok)?.extraInfo == "Credits available $20.00")
        precondition(AccountPageParser.parse(.xAI, text: "Current plan\n89% left\nAccount balance") == nil)
        print("Account page parsing passed")
    }
}
