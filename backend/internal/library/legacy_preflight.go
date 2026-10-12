package library

import (
	"encoding/json"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

// The prefix was verified under the same Store write lock. The new revision
// comes from vax.Create; admission needs its wire size, not another history read.
func (s *Store) preflightLegacyRevision(revision model.Revision, verifiedBytes int64) error {
	encoded, err := json.Marshal(revision)
	if err != nil {
		return fault.Encode(err)
	}
	size := int64(len(encoded))
	if size > int64(s.config.Storage.RecordMiB)*1024*1024 {
		return fault.New(fault.LimitExceeded, "revision data exceeds the read limit")
	}
	if size > int64(s.config.Storage.HistoryMiB)*1024*1024-verifiedBytes {
		return fault.New(fault.LimitExceeded, "aggregate history exceeds the read limit; adjust storage.historyMiB")
	}
	return nil
}
