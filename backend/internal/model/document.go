package model

type Section struct {
	Title string `json:"title"`
	Text  string `json:"text"`
}
type Sheet struct {
	Name string     `json:"name"`
	Rows [][]string `json:"rows"`
}
type Note struct {
	ID        string `json:"id"`
	Body      string `json:"body"`
	Quote     string `json:"quote"`
	Location  string `json:"location"`
	CreatedAt string `json:"createdAt"`
}
type AdoptionSource struct {
	BranchID       string `json:"branchId"`
	RevisionID     string `json:"revisionId"`
	BaseRevisionID string `json:"baseRevisionId"`
}
type Revision struct {
	ID          string          `json:"id"`
	ParentID    *string         `json:"parentId"`
	Kind        string          `json:"kind"`
	CreatedAt   string          `json:"createdAt"`
	Content     string          `json:"content"`
	Notes       []Note          `json:"notes"`
	PrevSAI     string          `json:"prevSAI"`
	SAI         string          `json:"sai"`
	Envelope    string          `json:"envelope"`
	BranchID    string          `json:"branchId,omitempty"`
	AdoptedFrom *AdoptionSource `json:"adoptedFrom,omitempty"`
}
type Document struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Filename     string    `json:"filename"`
	Format       string    `json:"format"`
	CreatedAt    string    `json:"createdAt"`
	UpdatedAt    string    `json:"updatedAt"`
	OriginalHash string    `json:"originalHash"`
	Sections     []Section `json:"sections"`
	Sheets       []Sheet   `json:"sheets"`
	Actor        string    `json:"actor"`
	Salt         string    `json:"salt"`
	Genesis      string    `json:"genesis"`
}
type Position struct {
	RevisionID string  `json:"revisionId"`
	Block      string  `json:"block"`
	Ratio      float64 `json:"ratio"`
	Percentage float64 `json:"percentage"`
	Section    int     `json:"section"`
	UpdatedAt  string  `json:"updatedAt"`
	Epoch      *string `json:"epoch,omitempty"`
}
type Manifest struct {
	Document      Document  `json:"document"`
	OriginalFile  string    `json:"originalFile"`
	OriginalType  string    `json:"originalType"`
	RevisionIDs   []string  `json:"revisionIds"`
	Progress      *Position `json:"progress,omitempty"`
	ProgressEpoch *string   `json:"progressEpoch,omitempty"`
}
type Book struct {
	Document
	Revisions    []Revision `json:"revisions"`
	OriginalPath string     `json:"originalPath"`
	Progress     *Position  `json:"progress"`
}
type Summary struct {
	ID            string  `json:"id"`
	Title         string  `json:"title"`
	Filename      string  `json:"filename"`
	Format        string  `json:"format"`
	UpdatedAt     string  `json:"updatedAt"`
	Head          string  `json:"head"`
	RevisionCount int     `json:"revisionCount"`
	Progress      float64 `json:"progress"`
}
type Draft struct {
	ID             string  `json:"id"`
	DocumentID     string  `json:"documentId"`
	BaseRevisionID string  `json:"baseRevisionId"`
	Version        string  `json:"version"`
	UpdatedAt      string  `json:"updatedAt"`
	Content        *string `json:"content,omitempty"`
	Body           string  `json:"body"`
	Quote          string  `json:"quote"`
	Location       string  `json:"location"`
	BranchID       string  `json:"branchId,omitempty"`
}
