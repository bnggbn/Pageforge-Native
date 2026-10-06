package library

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"strings"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

func migrateEvidence(w model.EvidenceWall) model.EvidenceWall {
	if w.SchemaVersion == 1 {
		w.Topics = []model.EvidenceTopic{{ID: model.AllEvidenceTopic, Name: "全部線索", Cards: w.Cards, Edges: w.Edges}}
		w.Cards, w.Edges = nil, nil
		w.ActiveTopic, w.SchemaVersion = model.AllEvidenceTopic, 2
	}
	return w
}

// Reading only exposes migration in memory. First successful write keeps a V1 backup.
func (s *Store) backupEvidenceV1(id, file string) error {
	data, err := readBounded(file, int64(s.config.EvidenceWall.LayoutMiB)*1024*1024)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var source model.EvidenceWall
	if err = json.Unmarshal(data, &source); err != nil {
		return err
	}
	if source.SchemaVersion != 1 {
		return nil
	}
	backup, err := s.safe("books", id, "evidence-wall.v1.backup.json")
	if err != nil {
		return err
	}
	if _, err = os.Stat(backup); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	stream, err := os.OpenFile(backup, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if os.IsExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err = stream.Write(data); err == nil {
		err = stream.Sync()
	}
	closeErr := stream.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		os.Remove(backup)
	}
	return err
}

func (s *Store) validateEvidence(w model.EvidenceWall, notes map[string]bool) error {
	if w.Revision != "" && !uuid.MatchString(w.Revision) {
		return fmt.Errorf("線索牆版本無效")
	}
	if w.SchemaVersion == 1 {
		if w.Topics != nil || w.ActiveTopic != "" {
			return fmt.Errorf("線索牆版本欄位無效")
		}
		return s.validateEvidenceTopic(model.EvidenceTopic{Cards: w.Cards, Edges: w.Edges}, notes)
	}
	c := s.config.EvidenceWall
	if w.SchemaVersion != 2 || w.Cards != nil || w.Edges != nil || len(w.Topics) < 1 || len(w.Topics) > c.MaxTopics {
		return fmt.Errorf("線索牆主題格式或容量無效")
	}
	ids, names := map[string]bool{}, map[string]bool{}
	for _, topic := range w.Topics {
		name := strings.TrimSpace(topic.Name)
		if !uuid.MatchString(topic.ID) ||
			ids[topic.ID] ||
			name == "" ||
			name != topic.Name ||
			len([]rune(name)) > c.TopicNameCharacters ||
			names[strings.ToLower(name)] {
			return fmt.Errorf("線索主題名稱或識別碼無效")
		}
		if topic.ID == model.AllEvidenceTopic && topic.Name != "全部線索" {
			return fmt.Errorf("預設線索主題不可改名")
		}
		ids[topic.ID], names[strings.ToLower(name)] = true, true
		if err := s.validateEvidenceTopic(topic, notes); err != nil {
			return err
		}
	}
	if !ids[model.AllEvidenceTopic] || !ids[w.ActiveTopic] {
		return fmt.Errorf("缺少預設或目前線索主題")
	}
	return nil
}

func (s *Store) validateEvidenceTopic(t model.EvidenceTopic, notes map[string]bool) error {
	c := s.config.EvidenceWall
	if t.Cards == nil || t.Edges == nil || len(t.Cards) > c.MaxCards || len(t.Edges) > c.MaxEdges {
		return fmt.Errorf("線索卡片或紅線容量無效")
	}
	cards := map[string]bool{}
	for _, card := range t.Cards {
		if !uuid.MatchString(card.NoteID) ||
			cards[card.NoteID] ||
			(notes != nil && !notes[card.NoteID]) ||
			math.IsNaN(card.X) ||
			math.IsInf(card.X, 0) ||
			math.IsNaN(card.Y) ||
			math.IsInf(card.Y, 0) ||
			card.X < 0 ||
			card.Y < 0 ||
			card.X > float64(c.CanvasWidth-280) ||
			card.Y > float64(c.CanvasHeight-240) {
			return fmt.Errorf("線索卡片位置或筆記來源無效")
		}
		cards[card.NoteID] = true
	}
	ids, pairs := map[string]bool{}, map[string]bool{}
	for _, edge := range t.Edges {
		a, b := edge.From, edge.To
		if a > b {
			a, b = b, a
		}
		pair := a + ":" + b
		if !uuid.MatchString(edge.ID) ||
			ids[edge.ID] ||
			pairs[pair] ||
			edge.From == edge.To ||
			!cards[edge.From] ||
			!cards[edge.To] ||
			len([]rune(edge.Label)) > 200 {
			return fmt.Errorf("紅線端點或標籤無效")
		}
		ids[edge.ID], pairs[pair] = true, true
	}
	return nil
}
