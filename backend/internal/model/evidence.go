package model

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
type EvidenceWall struct {
	SchemaVersion int            `json:"schemaVersion"`
	Revision      string         `json:"revision"`
	UpdatedAt     string         `json:"updatedAt"`
	Cards         []EvidenceCard `json:"cards"`
	Edges         []EvidenceEdge `json:"edges"`
}
