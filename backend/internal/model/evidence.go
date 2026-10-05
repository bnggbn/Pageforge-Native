package model

const AllEvidenceTopic = "00000000-0000-4000-8000-000000000001"

type EvidenceCard struct {
	NoteID string  `json:"noteId"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
}
type EvidenceEdge struct {
	ID    string `json:"id"`
	From  string `json:"from"`
	To    string `json:"to"`
	Label string `json:"label"`
}
type EvidenceTopic struct {
	ID    string         `json:"id"`
	Name  string         `json:"name"`
	Cards []EvidenceCard `json:"cards"`
	Edges []EvidenceEdge `json:"edges"`
}
type EvidenceWall struct {
	SchemaVersion int             `json:"schemaVersion"`
	Revision      string          `json:"revision"`
	UpdatedAt     string          `json:"updatedAt"`
	ActiveTopic   string          `json:"activeTopic,omitempty"`
	Topics        []EvidenceTopic `json:"topics,omitempty"`
	// Version 1 fields are accepted for migration, omitted from version 2 replies.
	Cards []EvidenceCard `json:"cards,omitempty"`
	Edges []EvidenceEdge `json:"edges,omitempty"`
}
