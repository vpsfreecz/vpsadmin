# This module handles translation from old parameter names to new ones.
# Old names are ugly and should be used only for communication with database.
# Class/module including this module must define method +compat_matrix+, that
# has to return hash, whose keys will be old param names and values new names.
module VpsAdmin::API::Compat
  def to_new(hash)
    ret = {}

    compat_matrix.each do |old, new|
      ret[new] = hash[old] if hash[old]
    end

    ret
  end

  def to_old(hash)
    ret = {}

    compat_matrix.each do |old, new|
      ret[old] = hash[new] if hash[new]
    end

    ret
  end
end
