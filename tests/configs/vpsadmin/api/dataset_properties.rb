VpsAdmin::API::DatasetProperties.register do
  property :atime do
    type :bool
    label 'Access time'
    desc 'Controls whether the access time for files is updated when they are read'
    default false
  end

  property :compression do
    type :bool
    label 'Compression'
    desc 'Toggle data compression in this dataset'
    default true
  end

  property :recordsize do
    type :integer
    label 'Record size'
    desc 'Specifies a suggested block size for files in the file system'
    default 128 * 1024

    validate do |raw|
      raw.between?(4096, 128 * 1024) && raw.nobits?(raw - 1)
    end
  end

  property :quota do
    type :integer
    label 'Quota'
    desc 'Limits the amount of space a dataset and all its descendants can consume'
    default 0
    inheritable false

    validate do |raw|
      raw >= 0
    end
  end

  property :refquota do
    type :integer
    label 'Reference quota'
    desc 'Limits the amount of space a dataset can consume'
    default 0
    inheritable false

    validate do |raw|
      raw >= 0
    end
  end

  property :relatime do
    type :bool
    label 'Relative access time'
    desc "Access time is only updated if the previous access time was earlier than the current modify or change time or if the existing access time hasn't been updated within the past 24 hours"
    default false
  end

  property :sync do
    type :string
    label 'Sync'
    desc 'Controls the behavior of synchronous requests'
    default 'standard'
    choices %w[standard disabled]
  end

  property :sharenfs do
    type :string
    label 'NFS share'
    desc 'Controls NFS sharing'
    default ''
  end

  property :used do
    type :integer
    label 'Used space'
    desc 'Amount of space used by dataset'
    default 0
    editable false
  end

  property :referenced do
    type :integer
    label 'Referenced space'
    desc 'Amount of space that is accessible to this dataset'
    default 0
    editable false
  end

  property :avail do
    type :integer
    label 'Available space'
    desc 'Amount of space left in dataset'
    default 0
    editable false
  end

  property :compressratio do
    type :float
    label 'Used compression ratio'
    desc 'Compression ratio for used space of this dataset'
    default 1.0
    editable false
  end

  property :refcompressratio do
    type :float
    label 'Referenced compression ratio'
    desc 'Compression ratio for referenced space of this dataset'
    default 1.0
    editable false
  end
end
