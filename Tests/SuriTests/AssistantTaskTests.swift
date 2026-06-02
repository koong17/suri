import Foundation
import Testing
@testable import Suri

struct AssistantTaskTests {
    @Test
    func activeJiraIssueIsDetectedFromStatusMetadata() {
        let task = AssistantTask(
            title: "Build admin dashboard",
            source: .jira,
            dueDate: nil,
            priority: .normal,
            status: .open,
            context: "TMS-8140",
            owner: "suah.kang",
            requiresUserReview: true,
            recommendedAction: "확인",
            metadata: [MetadataItem(label: "상태", value: "진행 중")]
        )

        #expect(task.isActiveJiraIssue)
    }

    @Test
    func reviewedJiraIssueIsNotActive() {
        let task = AssistantTask(
            title: "Reviewed Jira issue",
            source: .jira,
            dueDate: nil,
            priority: .urgent,
            status: .reviewed,
            context: "TMS-8140 진행 중",
            owner: "suah.kang",
            requiresUserReview: false,
            recommendedAction: "없음",
            metadata: [MetadataItem(label: "상태", value: "진행 중")]
        )

        #expect(!task.isActiveJiraIssue)
    }

    @Test
    func sortedForAssistantPrioritizesActiveJiraIssues() {
        let urgentGitLabTask = AssistantTask(
            title: "Urgent merge request",
            source: .gitLab,
            dueDate: Date(timeIntervalSince1970: 1_000),
            priority: .urgent,
            status: .waiting,
            context: "MR needs review",
            owner: "suah.kang",
            requiresUserReview: true,
            recommendedAction: "리뷰",
            metadata: []
        )
        let activeJiraTask = AssistantTask(
            title: "Active Jira issue",
            source: .jira,
            dueDate: Date(timeIntervalSince1970: 2_000),
            priority: .normal,
            status: .open,
            context: "TMS-8140",
            owner: "suah.kang",
            requiresUserReview: true,
            recommendedAction: "확인",
            metadata: [MetadataItem(label: "상태", value: "In Progress")]
        )

        let sortedTasks = [urgentGitLabTask, activeJiraTask].sortedForAssistant()

        #expect(sortedTasks.first?.id == activeJiraTask.id)
    }
}
