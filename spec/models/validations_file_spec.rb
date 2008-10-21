# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008 TIS Inc.
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

require File.dirname(__FILE__) + '/../spec_helper'

class ValidateFileClass
  include ValidationsFile

  attr_accessor :file
end

describe ValidationsFile do
  before do
    @vf = mock_model_class
    @muf = mock_uploaed_file
  end
  describe "#valid_presence_of_file" do
    describe "ファイルが設定されている場合" do
      it "trueを返すこと" do
        @vf.valid_presence_of_file(@muf).should be_true
      end
    end
    describe "ファイルが設定されていない場合" do
      it "falseを返ること" do
        @vf.valid_presence_of_file("string").should be_false
      end
      it "エラーが追加されること" do
        @vf.errors.should_receive(:add_to_base).with("ファイルが指定されていません。")
        @vf.valid_presence_of_file("string")
      end
    end
  end

  describe "#valid_extension_of_file" do
    describe "ファイルの形式が不正な場合" do
      it "エラーが追加されること" do
        @vf.errors.should_receive(:add_to_base).with("この形式のファイルは、アップロードできません。")
        SkipUtil.should_receive(:verify_extension?).and_return(false)
        @vf.valid_extension_of_file(@muf)
      end
    end
  end

  describe "#valid_size_of_file" do
    describe "ファイルサイズが0の場合" do
      it "エラーが追加されること" do
        @muf.stub!(:size).and_return(0)
        @vf.errors.should_receive(:add_to_base).with('存在しないもしくはサイズ０のファイルはアップロードできません。')
        @vf.valid_size_of_file(@muf)
      end
    end
    describe "ファイルサイズが最大値を超えている場合" do
      it "エラーが追加されること" do
        @muf.stub!(:size).and_return(INITIAL_SETTINGS['max_share_file_size'].to_i + 100)
        @vf.errors.should_receive(:add_to_base).with("#{INITIAL_SETTINGS['max_share_file_size'].to_i/1.megabyte}Mバイト以上のファイルはアップロードできません。")
        @vf.valid_size_of_file(@muf)
      end
    end
  end

  describe "#valid_max_size_per_owner_of_file" do
    describe "ファイルサイズがオーナーの最大許可容量を超えている場合" do
      it "エラーが追加されること" do
        @muf.stub!(:size).and_return(101)
        owner_symbol = "git:hoge"
        ValidationsFile::FileSizeCounter.should_receive(:per_owner).with(owner_symbol).and_return(INITIAL_SETTINGS['max_share_file_size_per_owner'].to_i - 100)
        @vf.errors.should_receive(:add_to_base).with("共有ファイル保存領域の利用容量が最大値を越えてしまうためアップロードできません。")
        @vf.valid_max_size_per_owner_of_file(@muf, owner_symbol)
      end
    end
  end

  describe "#valid_max_size_of_system_of_file" do
    describe "ファイルサイズがオーナーの最大許可容量を超えている場合" do
      it "エラーが追加されること" do
        @muf.stub!(:size).and_return(101)
        ValidationsFile::FileSizeCounter.should_receive(:per_system).and_return(INITIAL_SETTINGS['max_share_file_size_of_system'].to_i - 100)
        @vf.errors.should_receive(:add_to_base).with('システム全体における共有ファイル保存領域の利用容量が最大値を越えてしまうためアップロードできません。')
        @vf.valid_max_size_of_system_of_file(@muf)
      end
    end
  end

  def mock_model_class
    errors = mock('errors')
    errors.stub!(:add_to_base)

    vf = ValidateFileClass.new
    vf.stub!(:errors).and_return(errors)
    vf
  end
end

describe ValidationsFile::FileSizeCounter do
  describe ".per_owner" do
    before do
      ShareFile.should_receive(:total_share_file_size).and_return(100)
      BoardEntry.should_receive(:total_image_size).and_return(200)
    end
    it "ファイルサイズを返す" do
      ValidationsFile::FileSizeCounter.per_owner(@owner_symbol).should == 300
    end
  end
  describe ".per_system" do
    before do
      Dir.should_receive(:glob).with("#{ENV['SHARE_FILE_PATH']}/**/*\0#{ENV['IMAGE_PATH']}/**/*").and_return(["a", "a"])
      file = mock('file')
      file.stub!(:size).and_return(100)
      File.should_receive(:stat).with('a').at_least(:once).and_return(file)
    end
    it "ファイルサイズを返す" do
      ValidationsFile::FileSizeCounter.per_system.should == 200
    end
  end
end