class Article < ApplicationRecord
  include Post

  belongs_to :theme

  has_many :taggings, dependent: :destroy, as: :taggable
  has_many :tags, through: :taggings
  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations
  has_many :contributions, dependent: :destroy
  has_many :collection_posts, foreign_key: :collection_id, class_name: :Article
  has_many :views, dependent: :destroy

  has_one    :redirect, dependent: :destroy
  belongs_to :collection, foreign_key: :parent_id, class_name: :Article

  accepts_nested_attributes_for :contributions, reject_if: :all_blank, allow_destroy: true

  before_validation :generate_published_dates, on: [:create, :update]
  before_validation :downcase_content_format,  on: [:create, :update]
  before_validation :normalize_newlines,       on: [:create, :update]

  validates :short_path, uniqueness: true, unless: :short_path_blank?
  validates :tweet, length: { maximum: 115 }
  validates :summary, length: { maximum: 200 }

  before_save :update_or_create_redirect

  default_scope { order(published_at: :desc) }
  scope :chronological, -> { order(published_at: :desc) }
  scope :root,          -> { where(collection_id: nil) }
  scope :live,          -> { where("published_at < ?", Time.now) }
  scope :recent,        -> { where("published_at BETWEEN ? AND ?", Time.now - 2.days,  Time.now) }
  scope :last_2_weeks,  -> { where("published_at BETWEEN ? AND ?", Time.now - 2.weeks, Time.now) }
  scope :on,            lambda { |date| where("published_at BETWEEN ? AND ?", date.try(:beginning_of_day), date.try(:end_of_day)) }
  scope :next,          lambda { |article| unscoped.root.where("published_at > ?", article.published_at).live.published.order(published_at: :asc).limit(1) }
  scope :previous,      lambda { |article| root.where("published_at < ?", article.published_at).live.published.chronological.limit(1) }

  def path
    if published?
      published_at.strftime("/%Y/%m/%d/#{slug}")
    else
      "/drafts/articles/#{self.draft_code}"
    end
  end

 # Overwrites slug_exists? from Slug.  We allow duplicate slugs on different
 # published_at dates.
  def slug_exists?
    Article.on(published_at).where(slug: slug).exists?
  end

  def collection_root?
    collection_posts.any?
  end

  def in_collection?
    # TODO this is a hack
    collection_id.present?
  end

  def short_path_blank?
    short_path.blank?
  end

  def content_rendered
    Kramdown::Document.new(
      MarkdownMedia.parse(content.gsub("\n","\n\n")),
      input: content_format == "html" ? :html : :kramdown,
      remove_block_html_tags: false,
      transliterated_header_ids: true,
      html_to_native: true
    ).to_html.html_safe
  end

  def related
    related_articles = {}

    if categories.present?
      categories.each do |category|

        articles = []
        category.articles.published[0..7].each do |article|
          if article != self &&
             articles.length < 2 &&
             !related_articles.values.flatten.include?(article)
            articles << article
          end
        end

        related_articles[category] = articles
      end
    end

    related_articles
  end

  private

  def generate_published_dates
    if published_at.present?
      self.year  = published_at.year                     if published_at.year.present?
      self.month = published_at.month.to_s.rjust(2, "0") if published_at.month.present?
      self.day   = published_at.day.to_s.rjust(2, "0")   if published_at.day.present?
    end
  end

  def downcase_content_format
    self.content_format = self.content_format.downcase
  end

  def normalize_newlines
    tweet.gsub!("\r\n", "\n") if tweet.present?
    summary.gsub!("\r\n", "\n") if summary.present?
  end

  def update_or_create_redirect
    if short_path.present?

      if redirect.present?
        if short_path_changed? || slug_changed? || published_at_changed? || status_id_changed?
          redirect.update_attributes(source_path: "/" + self.short_path, target_path: self.path )
        end
      elsif Redirect.where(source_path: "/" + self.short_path).exists?
        errors.add(:short_path, ' is a path that already points to a redirect.')
      else
        if self.status.name == "published"
          Redirect.create(source_path: "/" + self.short_path, target_path: path, article_id: id)
        end
      end
    end

  end
end
