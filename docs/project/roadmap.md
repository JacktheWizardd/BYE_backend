# Product roadmap

This is a capability map, not a delivery schedule or authorization to enable a feature. See [Project status](PROJECT_STATUS.md) for recorded implementation and verification.

| Capability | Current boundary | Remaining work |
| --- | --- | --- |
| Course and section comparison | Implemented in native Mac and separate Windows source | Continue platform-specific verification and release preparation |
| Windows schedule API | Implemented locally, using supported imported terms and freshness-aware availability | Investigate stale backend synchronization separately; no new client release claimed |
| BYE student reviews | Website owns writing; Windows reads public BYE reviews independently from RMP | Native Mac integration and ongoing operational work |
| RMP information | Existing bounded retrieval and explicit identity handling | Preserve independent source labels and access requirements |
| Review-source toggle | Requested UI direction; separate source presentation currently exists | Design and implement BYE/RMP switching in shared UI as a separate task |
| Transfer evaluation | Future product goal | Define authoritative articulation sources, matching rules and acceptance criteria before implementation |
| Educational plans | Future product goal | Define plan input, requirements, validation and student workflow |
| AI review summaries | Disabled in current prepared Mac/Windows apps; research preserved | Evaluate evidence quality, correctness and privacy before any separately authorized activation |

Transfer evaluation and educational plans are documented separately because comparing existing sections does not establish transfer eligibility or degree completion. AI research results do not establish production readiness. BYE must not automatically choose or recommend professors.

For research history, see [AI experiments](../experiments/README.md). For schedule operations, see [PCC schedules](../schedules/README.md).
