class_name CampaignSetup
extends RefCounted
## The campaign chapter being started: plain data handed from the campaign screen to the
## battle scene (like SkirmishSetup). The battle reads CampaignSetup.current in _ready; a
## restart rebuilds the chapter from `start_state`, the progress as it was at the start.

static var current: CampaignSetup = null
## Set when a chapter ends: the main menu opens on the campaign screen.
static var returning: bool = false

var campaign: String = ""
var chapter: String = ""
var start_state: Dictionary = {}  ## CampaignProgress.to_dict() at the start of the chapter


static func make(p: CampaignProgress, chapter_id: String) -> CampaignSetup:
	var s := CampaignSetup.new()
	s.campaign = p.campaign
	s.chapter = chapter_id
	s.start_state = p.to_dict()
	return s


## A fresh copy of the progress at the start of the chapter.
func progress() -> CampaignProgress:
	return CampaignProgress.from_dict(start_state.duplicate(true))


func chapter_def() -> Dictionary:
	return CampaignCatalog.get_default().chapter(campaign, chapter)


func mission_def() -> Dictionary:
	return CampaignCatalog.get_default().mission(chapter_def())
