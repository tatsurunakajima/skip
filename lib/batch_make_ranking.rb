# SKIP（Social Knowledge & Innovation Platform）
# Copyright (C) 2008  TIS Inc.
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

require File.expand_path(File.dirname(__FILE__) + "/../config/environment")

# 1日分のランキング元データを生成
# 送信するデータは、送信日時点でのこれまでの累積値(!=前日からの差分)
# 表示時には、本バッチで生成したデータを集計するのみ。
class BatchMakeRanking < BatchBase

  def self.execute options
    unless exec_date = options[:exec_day]
      exec_date = Date.today.yesterday
    end 

    begin
      ActiveRecord::Base.transaction do
        # バッチのリラン用
        Ranking.destroy_all(['extracted_on = ?', exec_date])

        # アクセス数
        create_access_ranking exec_date

        # へー
        create_point_ranking exec_date

        # コメント数
        create_comment_ranking exec_date

        # 投稿数
        create_post_ranking exec_date

        # 訪問者数
        create_visited_ranking exec_date

        # コメンテータ
        create_commentator_ranking exec_date
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      e.backtrace.each { |line| log_error line}
    end
  end

private
  def self.create_access_ranking exec_date
    BoardEntryPoint.find(:all, :conditions => make_conditions("access_count > 0", exec_date)).each do |entrypoint|
      entry = entrypoint.board_entry
      if published? entry
        create_ranking_by_entry entry, entrypoint.access_count, "entry_access", exec_date
      end
    end
  end

  def self.create_point_ranking exec_date
    BoardEntryPoint.find(:all, :conditions => make_conditions("point > 0", exec_date)).each do |entrypoint|
      entry = entrypoint.board_entry 
      if published? entry
        create_ranking_by_entry entry, entrypoint.point, "entry_he", exec_date
      end
    end
  end

  def self.create_comment_ranking exec_date
    BoardEntry.find(:all, :conditions => make_conditions("board_entry_comments_count > 0", exec_date)).each do |entry|
      if published? entry
        create_ranking_by_entry entry, entry.board_entry_comments_count, "entry_comment", exec_date
      end
    end
  end

  def self.create_post_ranking exec_date
    BoardEntry.find(:all, :conditions => make_conditions("entry_type = 'DIARY'", exec_date), 
                    :select => "user_id, MAX(user_entry_no) as user_entry_no", 
                    :group => "user_id").each do |record|
      user = User.find(record.user_id) 
      create_ranking_by_user user, record.user_entry_no, "user_entry", exec_date
    end
  end

  def self.create_visited_ranking exec_date
    UserAccess.find(:all, :conditions => make_conditions("access_count > 0", exec_date)).each do |access|
      user = access.user
      create_ranking_by_user user, access.access_count, "user_access", exec_date
    end
  end

  def self.create_commentator_ranking exec_date
    # skip上に累積値を持たないため、導出
    sql = <<-SQL
          SELECT user_id,COUNT(*) AS comment_count
          FROM board_entry_comments
          WHERE user_id IN (
            SELECT distinct user_id
            FROM board_entry_comments
            WHERE DATE_FORMAT(updated_on,'%Y%m%d') = :commentator_conditions
          )
          -- 6月1日から9月1日で実行する場合に、6月1日分のデータを生成する際に6月1以前の分のみ対象にするため
          -- (6月1日以降のデータ入ってしまうと正常なデータにならない)
          AND DATE_FORMAT(updated_on,'%Y%m%d') <= :commentator_conditions
          GROUP BY user_id
          SQL
    BoardEntryComment.find_by_sql([sql, { :commentator_conditions => exec_date.strftime('%Y%m%d') }]).each do |record|
      user = User.find(record.user_id)
      create_ranking_by_user user, record.comment_count, "commentator", exec_date
    end
  end

  def self.make_conditions condition, exec_date
    [condition + " AND DATE_FORMAT(updated_on,'%Y%m%d') = ? ", exec_date.strftime('%Y%m%d')]
  end

  def self.published? entry
    entry.entry_publications.any?{|publication| publication.symbol == Symbol::SYSTEM_ALL_USER }
  end

  def self.create_ranking url, title, author, author_url, amount, contents_type, exec_date
    ranking = Ranking.new(
      :url => url,
      :title => title,
      :author => author,
      :author_url => author_url,
      :extracted_on => exec_date,
      :amount => amount,
      :contents_type => contents_type
    )
    ranking.save!
  end

  def self.create_ranking_by_entry entry, amount, contents_type, exec_date
    create_ranking page_url(entry.id), entry.title, entry.user.name, 
      user_url(entry.user.uid), amount, contents_type, exec_date
  end

  def self.create_ranking_by_user user, amount, contents_type, exec_date
    create_ranking user_url(user.uid), user.name, user.name,
      user_url(user.uid), amount, contents_type, exec_date
  end

  def self.user_url str
   ENV['SKIP_URL'] + "/user/" + str.to_s 
  end

  def self.page_url str
   ENV['SKIP_URL'] + "/page/" + str.to_s
  end
end


unless RAILS_ENV == 'test'
  # 引数は、シェルからの実行用。集計対象日を'YYYYMMDD'形式で渡せる。
  # cronからの日次実行時には、引数は不要。
  def parse_date str
    begin
      Date.parse(str)
    rescue => e
      BatchBase.log_error e
      e.backtrace.each { |line| BatchBase.log_error line }
      exit
    end
  end

  from_date = ARGV[0]
  to_date   = ARGV[1]

  unless to_date 
    exec_date = from_date ? parse_date(from_date) : Date.today.yesterday
    BatchMakeRanking.execution({:exec_day => exec_date}) 
  else
    (parse_date(from_date)..parse_date(to_date)).each do |exec_date|
      BatchMakeRanking.execution({:exec_day => exec_date}) 
    end 
  end
end
