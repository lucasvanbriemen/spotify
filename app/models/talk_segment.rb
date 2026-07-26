# A generated spoken radio segment (news bulletin, DJ intro or weather/time
# check). The id doubles as the audio filename in storage/audio, so it must
# satisfy the get-mp3 endpoint's /\A[a-zA-Z0-9-]+\z/ gate; the "talk-" prefix
# keeps it disjoint from ISRCs (which are 12 alphanumerics).
class TalkSegment < ApplicationRecord
  ID_PATTERN = /\Atalk-[a-z0-9-]+\z/
  KINDS = %w[news intro weather].freeze
  LANGUAGES = %w[nl en].freeze

  # MariaDB backs json columns with longtext + a json_valid CHECK, which the
  # adapter reports as text — declare the type so hashes round-trip as JSON.
  attribute :meta, :json

  validates :id, presence: true, format: { with: ID_PATTERN }
  validates :kind, inclusion: { in: KINDS }
  validates :language, inclusion: { in: LANGUAGES }

  scope :ready, -> { where(status: "ready") }

  def self.talk_id?(id)
    id.to_s.start_with?("talk-")
  end

  def audio_path
    SongCache.path(id)
  end

  def ready?
    status == "ready" && audio_path.file?
  end
end
