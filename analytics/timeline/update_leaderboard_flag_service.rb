class UpdateLeaderboardFlagService < ApplicationService
  attr_reader :company
  def initialize company_id
    @company = Company.find company_id
  end

  def call
    UserProfile.where(company_id: company.id).each do |user_profile|
      user_profile.set_company_document
      user_profile.save!
    end
  end
end