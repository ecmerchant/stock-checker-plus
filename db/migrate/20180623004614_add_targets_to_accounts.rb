class AddTargetsToAccounts < ActiveRecord::Migration[5.0]
  def change
    add_column :accounts, :yahoo, :boolean
    add_column :accounts, :mercari, :boolean
    add_column :accounts, :surugaya, :boolean
  end
end
