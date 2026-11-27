import Foundation

@main
@MainActor
enum IslandStateMachineTests {
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func main() {
        // 1. Default hoverExpandDelay MUST be 3.0 seconds
        let defaults = IslandStateMachine()
        precondition(defaults.hoverExpandDelay == 3.0, "Expected 3.0s default hoverExpandDelay")
        precondition(defaults.state == .hidden)

        // 2. Immediate hover never expands at 0ms, and mouseLeft cancels before dwell completes
        let fsm = IslandStateMachine()
        fsm.openOnHover = true
        fsm.hoverExpandDelay = 0.08
        fsm.mouseEntered()
        precondition(fsm.state == .hidden, "Hover must not expand immediately on enter")
        pump(0.03)
        fsm.mouseLeft()
        pump(0.08)
        precondition(fsm.state == .hidden, "Leaving before hoverExpandDelay must cancel hover open")

        // 3. Continuous hover for full dwell opens .home with openedByHover = true
        fsm.mouseEntered()
        precondition(fsm.state == .hidden)
        pump(0.11)
        precondition(fsm.state == .home, "Continuous hover past dwell must expand to .home")
        precondition(fsm.openedByHover == true)

        // 4. Clicking opens immediately (0ms) even while hover timer is pending
        let clickFsm = IslandStateMachine()
        clickFsm.openOnHover = true
        clickFsm.hoverExpandDelay = 3.0
        clickFsm.mouseEntered()
        precondition(clickFsm.state == .hidden)
        clickFsm.click()
        precondition(clickFsm.state == .home, "Click must open immediately without waiting 3s")
        precondition(clickFsm.openedByHover == false)

        print("✓ IslandStateMachine 3s hover dwell & instant click tests passed")
    }
}
